# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# child tf module inherits AWS region from provider in root module
data "aws_region" "current" {}

# child tf module inherits AWS account ID from provider in root module
data "aws_caller_identity" "current" {}

# get the current AWS partition (aws, aws-us-gov, aws-cn)
data "aws_partition" "current" {}

# lookup existing hosted zone when DNS_NAME is provided
data "aws_route53_zone" "existing" {
  count        = var.DNS_NAME != "" ? 1 : 0
  name         = join(".", slice(split(".", var.DNS_NAME), 1, length(split(".", var.DNS_NAME))))
  private_zone = true
  vpc_id       = data.aws_vpc.selected.id
}

locals {
  # child tf module inherits AWS region from provider in root module
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  asg_name   = "${var.PROXY_BASENAME}-asg"
  # determine zone ID based on whether we're creating a new zone or using existing
  r53_zone_id = var.DNS_NAME == "" ? aws_route53_zone.knfsd[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  r53_fqdn    = var.DNS_NAME == "" ? aws_route53_zone.knfsd[0].name : var.DNS_NAME
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
  name              = "/knfsd/lambda/static-ip/${var.PROXY_BASENAME}"
  retention_in_days = 30
  tags              = local.tags
}

# Lambda function to manage secondary ENI on instances in an EC2 ASG
resource "aws_lambda_function" "static_ip" {
  depends_on    = [data.archive_file.static_ip_zip, aws_cloudwatch_log_group.lambda_static_ip]
  function_name = "${var.PROXY_BASENAME}-static-ip"
  description   = "Lambda Python function to manage secondary ENI on instances in an EC2 ASG"
  role          = local.lambda_static_ip_role_arn
  handler       = "static_ip.lambda_handler"
  architectures = ["arm64"]
  runtime       = "python3.14"
  timeout       = 600
  filename      = "${path.module}/resources/static_ip.zip"
  # nosemgrep: aws-lambda-environment-unencrypted
  environment {
    variables = {
      USER_AGENT     = "AWSSOLUTION/SO9129/${var.VERSION}"
      VERSION        = var.VERSION
      PROXY_BASENAME = var.PROXY_BASENAME
      SUBNET         = var.SUBNET
      R53_ZONE_ID    = local.r53_zone_id
      R53_FQDN       = local.r53_fqdn
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
  tags                           = local.tags
}

# IAM role for the Lambda function (skipped when EXISTING_LAMBDA_ROLE_ARN is set)
resource "aws_iam_role" "lambda_static_ip" {
  count       = var.EXISTING_LAMBDA_ROLE_ARN == "" ? 1 : 0
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
  tags                  = local.tags
}

locals {
  # use the pre-existing Lambda role when provided, otherwise the one created by this module
  lambda_static_ip_role_arn = var.EXISTING_LAMBDA_ROLE_ARN != "" ? var.EXISTING_LAMBDA_ROLE_ARN : aws_iam_role.lambda_static_ip[0].arn
}

# custom IAM policy for Lambda statc_ip function (skipped when EXISTING_LAMBDA_ROLE_ARN is set)
resource "aws_iam_policy" "lambda_static_ip" {
  count       = var.EXISTING_LAMBDA_ROLE_ARN == "" ? 1 : 0
  name        = "${var.PROXY_BASENAME}-lambda-static-ip-policy"
  description = "Policy for Lambda to manage persistent secondary ENI on instances in an EC2 ASG"
  tags        = local.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = [
          "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/knfsd/lambda/static-ip/*:*",
          "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/knfsd/lambda/static-ip/*:log-stream:*"
        ]
      },
      {
        Action = [
          "autoscaling:CompleteLifecycleAction"
        ],
        Effect   = "Allow",
        Resource = "arn:${local.partition}:autoscaling:${local.region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"
      },
      {
        Action = [
          "ec2:CreateNetworkInterface"
        ],
        Effect = "Allow",
        Resource = [
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:network-interface/*",
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:subnet/${var.SUBNET}",
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:security-group/*"
        ]
      },
      {
        Action = [
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        Effect = "Allow",
        Resource = [
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:network-interface/*",
          "arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*"
        ]
      },
      {
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "route53:ChangeResourceRecordSets"
        ],
        Effect   = "Allow",
        Resource = "arn:${local.partition}:route53:::hostedzone/${local.r53_zone_id}"
      }
    ]
  })
}

# attach custom IAM policy to "lambda_static_ip" role (skipped when EXISTING_LAMBDA_ROLE_ARN is set)
resource "aws_iam_role_policy_attachment" "lambda_static_ip" {
  count      = var.EXISTING_LAMBDA_ROLE_ARN == "" ? 1 : 0
  role       = aws_iam_role.lambda_static_ip[0].name
  policy_arn = aws_iam_policy.lambda_static_ip[0].arn
}

# LAUNCHING: EventBridge Rule for launching instances
resource "aws_cloudwatch_event_rule" "instance_launching" {
  name        = "${var.PROXY_BASENAME}-knfsd-instance-launching"
  description = "Capture EC2 KNFSD instance launching events"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-launch Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [local.asg_name]
    }
  })
  tags = local.tags
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

# TERMINATING: EventBridge Rule for terminating instances
resource "aws_cloudwatch_event_rule" "instance_terminating" {
  name        = "${var.PROXY_BASENAME}-knfsd-instance-terminating"
  description = "Capture EC2 KNFSD instance terminating events"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-terminate Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [local.asg_name]
    }
  })
  tags = local.tags
}

# TERMINATING: EventBridge target for terminating instances
resource "aws_cloudwatch_event_target" "instance_terminating_target" {
  rule = aws_cloudwatch_event_rule.instance_terminating.name
  arn  = aws_lambda_function.static_ip.arn
}

# TERMINATING: Lambda permission for EventBridge terminating instances
resource "aws_lambda_permission" "allow_eventbridge_terminating" {
  statement_id  = "AllowExecutionFromEventBridgeTerminating"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.static_ip.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_terminating.arn
}

# TERMINATED: EventBridge Rule for terminated instances
resource "aws_cloudwatch_event_rule" "instance_terminated" {
  name        = "${var.PROXY_BASENAME}-knfsd-instance-terminated"
  description = "Capture EC2 KNFSD instance terminated events"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance Terminate Successful"]
    detail = {
      AutoScalingGroupName = [local.asg_name]
    }
  })
  tags = local.tags
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
