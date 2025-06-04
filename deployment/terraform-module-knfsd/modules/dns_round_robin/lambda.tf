/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# get the current AWS region
data "aws_region" "current" {}

# get the current AWS account id
data "aws_caller_identity" "current" {}

locals {
  aws_region = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
  asg_name   = "${var.PROXY_BASENAME}-asg"
}

# create zip file of the python script for the Lambda function
data "archive_file" "static_ip_zip" {
  type             = "zip"
  source_file      = "${path.module}/resources/static_ip.py"
  output_file_mode = "0755"
  output_path      = "${path.module}/resources/static_ip.zip"
}

# nosemgrep: aws-cloudwatch-log-group-unencrypted, missing-cloudwatch-log-group-kms-key
resource "aws_cloudwatch_log_group" "lambda_static_ip" {
  name              = "knfsd/lambda/${var.PROXY_BASENAME}-static-ip"
  retention_in_days = 7
}

# Lambda function to manage secondary ENI on instances in an EC2 ASG
resource "aws_lambda_function" "static_ip" {
  depends_on    = [data.archive_file.static_ip_zip, aws_route53_zone.nfsproxy]
  function_name = "${var.PROXY_BASENAME}-static-ip"
  description   = "Lambda Python function to manage secondary ENI on instances in an EC2 ASG"
  role          = aws_iam_role.lambda_static_ip.arn
  handler       = "static_ip.lambda_handler"
  architectures = ["arm64"]
  runtime       = "python3.13"
  timeout       = 600
  filename      = "${path.module}/resources/static_ip.zip"
  # nosemgrep: aws-lambda-environment-unencrypted
  environment {
    variables = {
      PROXY_BASENAME = var.PROXY_BASENAME
      SUBNET         = var.SUBNET
      R53_ZONE_ID    = aws_route53_zone.nfsproxy.zone_id
      R53_ZONE_NAME  = aws_route53_zone.nfsproxy.name
    }
  }
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda_static_ip.name
  }
  tracing_config {
    mode = "Active"
  }
  reserved_concurrent_executions = 1
}

# IAM role for the Lambda function
resource "aws_iam_role" "lambda_static_ip" {
  name        = "${var.PROXY_BASENAME}-static-ip-role"
  description = "IAM role for the Lambda static_ip function"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  force_detach_policies = true
}

# custom IAM policy for Lambda statc_ip function
resource "aws_iam_policy" "lambda_static_ip" {
  depends_on  = [aws_route53_zone.nfsproxy]
  name        = "${var.PROXY_BASENAME}-lambda-static-ip-policy"
  description = "Policy for Lambda to manage persistent secondary ENI on instances in an EC2 ASG"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:knfsd/lambda/${var.PROXY_BASENAME}-static-ip:*",
          "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:knfsd/lambda/${var.PROXY_BASENAME}-static-ip:log-stream:*"
        ]
      },
      {
        Action = [
          "autoscaling:CompleteLifecycleAction"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:autoscaling:${local.aws_region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"
      },
      {
        Action = [
          "ec2:CreateNetworkInterface"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:ec2:${local.aws_region}:${local.account_id}:network-interface/*",
          "arn:aws:ec2:${local.aws_region}:${local.account_id}:subnet/${var.SUBNET}",
          "arn:aws:ec2:${local.aws_region}:${local.account_id}:security-group/*"
        ]
      },
      {
        Action = [
          "ec2:AttachNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:CreateTags"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:ec2:${local.aws_region}:${local.account_id}:network-interface/*",
          "arn:aws:ec2:${local.aws_region}:${local.account_id}:instance/*"
        ]
      },
      {
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "route53:ChangeResourceRecordSets"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:route53:::hostedzone/${aws_route53_zone.nfsproxy.zone_id}"
      }
    ]
  })
}

# attach custom IAM policy to "lambda_static_ip" role
resource "aws_iam_role_policy_attachment" "lambda_static_ip" {
  role       = aws_iam_role.lambda_static_ip.name
  policy_arn = aws_iam_policy.lambda_static_ip.arn
}

# LAUNCHING: EventBridge Rule for launching instances
resource "aws_cloudwatch_event_rule" "instance_launching" {
  name        = "capture-instance-launching"
  description = "Capture EC2 nfsproxy instance launching events"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-launch Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [local.asg_name]
    }
  })
}

# LAUNCHING: EventBridge target for launching instances
resource "aws_cloudwatch_event_target" "instance_launching_target" {
  rule = aws_cloudwatch_event_rule.instance_launching.name
  arn  = aws_lambda_function.static_ip.arn
}

# LAUNCHING: Lambda permission for EventBridge launching instances
resource "aws_lambda_permission" "allow_eventbridge_launching" {
  statement_id  = "AllowExecutionFromEventBridgeLaunching"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.static_ip.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_launching.arn
}

# TERMINATED: EventBridge Rule for terminated instances
resource "aws_cloudwatch_event_rule" "instance_terminated" {
  name        = "capture-instance-terminated"
  description = "Capture EC2 nfsproxy instance terminated events"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance Terminate Successful"]
    detail = {
      AutoScalingGroupName = [local.asg_name]
    }
  })
}

# TERMINATED: EventBridge target for terminated instances
resource "aws_cloudwatch_event_target" "instance_terminated_target" {
  rule = aws_cloudwatch_event_rule.instance_terminated.name
  arn  = aws_lambda_function.static_ip.arn
}

# TERMINATED: Lambda permission for EventBridge terminated instances
resource "aws_lambda_permission" "allow_eventbridge_terminated" {
  statement_id  = "AllowExecutionFromEventBridgeTerminated"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.static_ip.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_terminated.arn
}
