/*
 * Copyright 2022 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.44.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/database/1.1.0-alpha.26"
    ]
  }
}

# generate a random name for the db instance
# example: "fsids-a1b2c3d4"
resource "random_id" "name" {
  prefix      = "${var.NAME_PREFIX}-"
  byte_length = 4
  keepers = {
    region = local.region,
    subnet = var.SUBNET
  }
}

# get the current AWS account id
data "aws_caller_identity" "current" {}

# get the selected subnet
data "aws_subnet" "selected" {
  id = var.SUBNET
}

# get the selected VPC
data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

# local variables
locals {
  tags            = { "knfsd-file-cache:version" = var.VERSION }
  name            = coalesce(var.NAME, random_id.name.hex)
  db_user         = "fsidd"
  db_name         = "fsids"
  account_id      = data.aws_caller_identity.current.account_id
  az              = data.aws_subnet.selected.availability_zone
  region          = regex("^([a-z]+-[a-z]+-[0-9]+)", local.az)[0]
  vpc_id          = data.aws_vpc.selected.id
  vpc_cidr        = length(var.VPC_CIDR) > 0 ? var.VPC_CIDR : [data.aws_vpc.selected.cidr_block]
  is_windows      = can(env("USERPROFILE"))
  assume_role_arn = var.ASSUME_ROLE_ARN != null ? var.ASSUME_ROLE_ARN : ""
}

# create the rds db instance, identifier=60 chars max + ("db-")
# https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html
# nosemgrep: aws-rds-multiaz-not-enabled, aws-db-instance-no-logging
resource "aws_db_instance" "fsids" {
  # db configuration
  identifier               = "${local.name}-fsids"
  db_name                  = local.db_name
  engine                   = "postgres"
  engine_version           = "18.3"
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  parameter_group_name     = aws_db_parameter_group.fsids_pg.name
  username                 = var.MASTER_USERNAME # master db user
  instance_class           = var.INSTANCE_CLASS
  allocated_storage        = 20
  max_allocated_storage    = 40
  storage_type             = "gp3"
  tags                     = local.tags

  # db network config
  availability_zone = local.az
  db_subnet_group_name = (
    var.FSID_DB_SUBNET_GROUP_NAME != null
    ? var.FSID_DB_SUBNET_GROUP_NAME
    : one(aws_db_subnet_group.fsids[*].name)
  )
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = var.ENABLE_PUBLIC_IP

  # db encryption
  storage_encrypted = true

  # managed master user via AWS Secrets Manager
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  # db perf insights, enhanced monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 30
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn

  # db upgrade, backup, snapshots
  auto_minor_version_upgrade = true
  backup_retention_period    = 7
  deletion_protection        = var.DELETION_PROTECTION
  skip_final_snapshot        = true
  copy_tags_to_snapshot      = true
}

# db subnet group (only created when the user opts-in via FSID_DB_SUBNET_IDS)
resource "aws_db_subnet_group" "fsids" {
  count       = var.FSID_DB_SUBNET_IDS != null ? 1 : 0
  name        = "${local.name}-db-subnet-group"
  description = "DB subnet group for ${local.name}"
  subnet_ids  = var.FSID_DB_SUBNET_IDS
  tags        = merge(local.tags, { Name = "${local.name}-db-subnet-group" })
}

# db security group
resource "aws_security_group" "db_sg" {
  name        = "${local.name}-postgres-sg"
  description = "knfsd security group for PostgreSQL RDS instance"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-postgres-sg" })
}

# db ingress rule
resource "aws_vpc_security_group_ingress_rule" "db_ingress" {
  for_each          = { for idx, cidr in local.vpc_cidr : tostring(idx) => cidr }
  security_group_id = aws_security_group.db_sg.id
  description       = "Allow PostgreSQL access from VPC"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value
  tags              = merge(local.tags, { Name = "tcp-5432-postgres" })
}

# db egress rule
resource "aws_vpc_security_group_egress_rule" "db_egress" {
  for_each          = { for idx, cidr in local.vpc_cidr : tostring(idx) => cidr }
  security_group_id = aws_security_group.db_sg.id
  description       = "Allow all outbound traffic to VPC"
  ip_protocol       = "-1" # all protocols
  cidr_ipv4         = each.value
  tags              = merge(local.tags, { Name = "egress-all-vpc" })
}

# db parameter group
resource "aws_db_parameter_group" "fsids_pg" {
  name        = "${local.name}-pg"
  description = "DB parameter group for ${local.name}"
  family      = "postgres18"
  tags        = local.tags
}

# enhanced monitoring role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name                  = "${local.name}-rds-enhanced-monitoring"
  assume_role_policy    = data.aws_iam_policy_document.rds_enhanced_monitoring.json
  force_detach_policies = true
  tags                  = local.tags
}

# attach enhanced monitoring policy to role
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# policy to allow assume role by enhanced monitoring service
# protect against confused deputy with SourceArn and SourceAccount
data "aws_iam_policy_document" "rds_enhanced_monitoring" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:rds:${local.region}:${local.account_id}:db:*"]
    }
  }
}

# IAM default policy for rds-db:connect database access (referenced by "terraform-module-knfsd/iam.tf" via "database/outputs.tf")
resource "aws_iam_policy" "db_policy" {
  name   = "${local.name}-rds-auth-policy"
  policy = data.aws_iam_policy_document.db_role_document.json
  tags   = local.tags
}

# IAM default policy document to allow rds-db:connect database access
data "aws_iam_policy_document" "db_role_document" {
  statement {
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${aws_db_instance.fsids.id}/${local.db_user}"]
  }
}

# Docker-based Lambda package creation
resource "null_resource" "lambda_package" {
  provisioner "local-exec" {
    when        = create
    working_dir = path.module
    interpreter = local.is_windows ? ["git-bash", "-c"] : ["/bin/bash", "-c"]
    command     = "./resources/docker-build.sh"
  }
}

# lambda-db-setup security group
resource "aws_security_group" "lambda_db_setup_sg" {
  name        = "${local.name}-lambda-db-setup-sg"
  description = "knfsd security group for Lambda db-setup function"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-lambda-db-setup-sg" })
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow all inbound traffic from ${local.name}-lambda-db-setup-sg"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = local.vpc_cidr
    description = "Allow all outbound traffic to VPC"
  }
}

# Lambda function to set up database
resource "aws_lambda_function" "db_setup" {
  depends_on    = [null_resource.lambda_package]
  function_name = "${local.name}-db-setup"
  description   = "Lambda Python function to configure the RDS PostgreSQL database"
  role          = aws_iam_role.lambda_db_setup.arn
  handler       = "db_setup.lambda_handler"
  architectures = ["x86_64"] # always use x86_64 only
  runtime       = "python3.14"
  timeout       = 15
  filename      = "${path.module}/resources/db_setup.zip"
  # nosemgrep: aws-lambda-environment-unencrypted
  environment {
    variables = {
      USER_AGENT         = "AWSSOLUTION/SO9129/${var.VERSION}"
      DB_ADDRESS         = aws_db_instance.fsids.address
      DB_PORT            = aws_db_instance.fsids.port
      DB_USER            = local.db_user
      DB_NAME            = local.db_name
      DB_SECRET_ENDPOINT = aws_vpc_endpoint.lambda_db_setup.dns_entry[0].dns_name
      DB_SECRET_REGION   = local.region
      DB_SECRET_NAME     = aws_db_instance.fsids.master_user_secret[0].secret_arn
    }
  }
  vpc_config {
    subnet_ids         = [var.SUBNET]
    security_group_ids = [aws_security_group.lambda_db_setup_sg.id]
  }
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda_db_setup.name
  }
  tracing_config {
    mode = "Active"
  }
  tags = local.tags
}

# CloudWatch log group for Lambda function
# nosemgrep: aws-cloudwatch-log-group-unencrypted, missing-cloudwatch-log-group-kms-key
resource "aws_cloudwatch_log_group" "lambda_db_setup" {
  name              = "knfsd/lambda/db-setup/${local.name}"
  retention_in_days = 30
  tags              = local.tags
}

# VPC endpoint for Lambda function to access Secrets Manager
resource "aws_vpc_endpoint" "lambda_db_setup" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.SUBNET]
  private_dns_enabled = false
  security_group_ids  = [aws_security_group.lambda_db_setup_sg.id]
  tags                = local.tags
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_db_setup" {
  name        = "${local.name}-lambda-db-setup"
  description = "IAM role for the Lambda db_setup function"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  force_detach_policies = true
  tags                  = local.tags
}

# attach Lambda VPC access/CW logging policy to role
resource "aws_iam_role_policy_attachment" "lambda_db_setup" {
  role       = aws_iam_role.lambda_db_setup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# custom IAM policy to retrieve master password from Secrets Manager
resource "aws_iam_role_policy" "lambda_db_setup" {
  name = "${local.name}-lambda-db-setup-policy"
  role = aws_iam_role.lambda_db_setup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.fsids.master_user_secret[0].secret_arn
    }]
  })
}

# trigger Lambda function after RDS instance is created
resource "null_resource" "trigger_lambda_after_rds" {
  depends_on = [aws_lambda_function.db_setup]

  # This provisioner will automatically assume the role specified in var.ASSUME_ROLE_ARN
  # if provided, otherwise it will use the existing AWS credentials from the environment.
  # This is useful for CI/CD pipelines where you need to assume a specific role for
  # AWS CLI commands while Terraform uses a different role via the AWS provider.
  provisioner "local-exec" {
    when        = create
    working_dir = path.module
    interpreter = local.is_windows ? ["git-bash", "-c"] : ["/bin/bash", "-c"]
    command     = <<-EOF
      set -e
      echo "Starting database setup..."

      # Check if role assumption is required
      if [ -n "${local.assume_role_arn}" ]; then
        echo "Assuming role: ${local.assume_role_arn}"
        # Assume the role and get temporary credentials
        ROLE_CREDS=$(aws sts assume-role --role-arn "${local.assume_role_arn}" --role-session-name "terraform-lambda-invoke" --output json)
        export AWS_ACCESS_KEY_ID=$(echo $ROLE_CREDS | jq -r '.Credentials.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(echo $ROLE_CREDS | jq -r '.Credentials.SecretAccessKey')
        export AWS_SESSION_TOKEN=$(echo $ROLE_CREDS | jq -r '.Credentials.SessionToken')
        echo "Role assumption completed successfully"
      else
        echo "No role assumption required, using existing AWS credentials"
      fi

      echo "Invoking Lambda function..."
      aws lambda invoke --region ${local.region} --function-name ${aws_lambda_function.db_setup.function_name} response.json

      # Check if the Lambda invocation itself succeeded
      if [ $? -ne 0 ]; then
        echo "ERROR: Lambda invocation failed"
        rm -f response.json
        exit 1
      fi

      # Parse the Lambda response and check statusCode
      STATUS_CODE=$(jq -r '.statusCode' response.json)

      if [ "$STATUS_CODE" != "200" ]; then
        echo "ERROR: Lambda function returned error status: $STATUS_CODE"
        echo "Response body:"
        jq -r '.body' response.json
        rm -f response.json
        exit 1
      fi

      echo "Lambda function executed successfully"
      jq -r '.body' response.json
      rm -f response.json
    EOF
  }
}

# cleanup (destroy) single-shot Lambda components after execution (optional, causes longer terraform apply time)
# resource "null_resource" "cleanup_lambda" {
#   depends_on = [null_resource.trigger_lambda_after_rds]

#   provisioner "local-exec" {
#     when    = create
#     command = <<-EOT
#       rm -f ${path.module}/resources/db_setup.zip
#       terraform destroy -auto-approve \
#         -target=aws_lambda_function.db_setup \
#         -target=aws_vpc_endpoint.lambda_db_setup \
#         -target=aws_security_group.lambda_db_setup_sg > /dev/null
#     EOT
#   }

#   provisioner "local-exec" {
#     when    = create
#     command = <<-EOT
#       terraform destroy -auto-approve \
#         -target=aws_iam_role.lambda_db_setup \
#         -target=aws_iam_role_policy_attachment.lambda_db_setup \
#         -target=aws_iam_role_policy.lambda_db_setup > /dev/null
#     EOT
#   }
# }

# this solution collects anonymous operational metrics to help AWS improve the quality of features of the solution
resource "aws_cloudformation_stack" "metrics_database" {
  name          = "${local.name}-metrics-database"
  on_failure    = "DO_NOTHING"
  tags          = local.tags
  template_body = <<STACK
    {
        "AWSTemplateFormatVersion": "2010-09-09",
        "Description": "(SO9129) - KNFSD-File-Cache. Version v${var.VERSION}",
        "Resources": {
            "EmptyResource": {
                "Type": "AWS::CloudFormation::WaitConditionHandle"
            }
        }
    }
    STACK
}
