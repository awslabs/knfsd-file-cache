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
      version = "~> 5.99.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }
  }
}

# generate a random name for the db instance
# example: "fsids-a1b2c3d4"
resource "random_id" "name" {
  prefix      = "${var.NAME_PREFIX}-"
  byte_length = 4
  keepers = {
    region = var.REGION,
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
  name           = coalesce(var.NAME, random_id.name.hex)
  db_user        = "fsidd"
  db_name        = "fsids"
  account_id     = data.aws_caller_identity.current.account_id
  az             = data.aws_subnet.selected.availability_zone
  vpc_id         = data.aws_vpc.selected.id
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
  is_windows     = can(env("USERPROFILE"))
}

# create the rds db instance, identifier=60 chars max + ("db-")
# https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html
# nosemgrep: aws-rds-multiaz-not-enabled, aws-db-instance-no-logging
resource "aws_db_instance" "fsids" {
  # db configuration
  identifier               = local.name
  db_name                  = local.db_name
  engine                   = "postgres"
  engine_version           = "17.5"
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  parameter_group_name     = aws_db_parameter_group.fsids_pg.name
  username                 = var.MASTER_USERNAME # master db user
  instance_class           = var.INSTANCE_CLASS
  allocated_storage        = 20
  max_allocated_storage    = 40
  storage_type             = "gp3"

  # db network config
  availability_zone      = local.az
  db_subnet_group_name   = var.FSID_DB_SUBNET_GROUP_NAME
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

# db security group
resource "aws_security_group" "db_sg" {
  name        = "${local.name}-postgres-sg"
  description = "knfsd security group for PostgreSQL RDS instance"
  vpc_id      = local.vpc_id
  tags = {
    Name = "${local.name}-postgres-sg"
  }
}

# db ingress rule
resource "aws_vpc_security_group_ingress_rule" "db_ingress" {
  security_group_id = aws_security_group.db_sg.id
  description       = "Allow PostgreSQL access from knfsd security group"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = local.vpc_cidr_block
}

# db egress rule
resource "aws_vpc_security_group_egress_rule" "db_egress" {
  security_group_id = aws_security_group.db_sg.id
  description       = "Allow all outbound traffic to knfsd security group"
  ip_protocol       = "-1" # all protocols
  cidr_ipv4         = local.vpc_cidr_block
}

# db parameter group
resource "aws_db_parameter_group" "fsids_pg" {
  name        = "${local.name}-pg"
  description = "DB parameter group for ${local.name}"
  family      = "postgres17"
}

# enhanced monitoring role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name                  = "${local.name}-rds-enhanced-monitoring"
  assume_role_policy    = data.aws_iam_policy_document.rds_enhanced_monitoring.json
  force_detach_policies = true
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
      values   = ["arn:aws:rds:${var.REGION}:${local.account_id}:db:*"]
    }
  }
}

# IAM default policy for rds-db:connect database access (referenced by "terraform-module-knfsd/iam.tf" via "database/outputs.tf")
resource "aws_iam_policy" "db_policy" {
  name   = "${local.name}-rds-auth-policy"
  policy = data.aws_iam_policy_document.db_role_document.json
}

# IAM default policy document to allow rds-db:connect database access
data "aws_iam_policy_document" "db_role_document" {
  statement {
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.REGION}:${local.account_id}:dbuser:${aws_db_instance.fsids.id}/${local.db_user}"]
  }
}

# Docker-based Lambda package creation
resource "null_resource" "lambda_package" {
  provisioner "local-exec" {
    when        = create
    working_dir = path.module
    interpreter = local.is_windows ? ["git-bash", "-c"] : ["/bin/bash", "-c"]
    # ./resources/docker-build.sh $ARCH $KNFSD_PYTHON_VERSION $KNFSD_PSYCOPG_VERSION
    # ./resources/docker-build.sh linux/arm64 3.13.3 3.2.7
    command = "./resources/docker-build.sh"
  }
}

# lambda-db-setup security group
resource "aws_security_group" "lambda_db_setup_sg" {
  name        = "${local.name}-lambda-db-setup-sg"
  description = "knfsd security group for Lambda db-setup function"
  vpc_id      = local.vpc_id
  tags = {
    Name = "${local.name}-lambda-db-setup-sg"
  }
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
    cidr_blocks = [local.vpc_cidr_block]
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
  architectures = ["arm64"]
  runtime       = "python3.13"
  timeout       = 15
  filename      = "${path.module}/resources/db_setup.zip"
  # nosemgrep: aws-lambda-environment-unencrypted
  environment {
    variables = {
      DB_ADDRESS         = aws_db_instance.fsids.address
      DB_PORT            = aws_db_instance.fsids.port
      DB_USER            = local.db_user
      DB_NAME            = local.db_name
      DB_SECRET_ENDPOINT = aws_vpc_endpoint.lambda_db_setup.dns_entry[0].dns_name
      DB_SECRET_REGION   = var.REGION
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
}

# CloudWatch log group for Lambda function
# nosemgrep: aws-cloudwatch-log-group-unencrypted, missing-cloudwatch-log-group-kms-key
resource "aws_cloudwatch_log_group" "lambda_db_setup" {
  name              = "knfsd/lambda/${local.name}-db-setup"
  retention_in_days = 7
}

# VPC endpoint for Lambda function to access Secrets Manager
resource "aws_vpc_endpoint" "lambda_db_setup" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.REGION}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.SUBNET]
  private_dns_enabled = false
  security_group_ids  = [aws_security_group.lambda_db_setup_sg.id]
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

  provisioner "local-exec" {
    when    = create
    command = "aws lambda invoke --function-name ${aws_lambda_function.db_setup.function_name} response.json"
  }
}

# destroy single-shot Lambda components after execution (optional, causes longer terraform apply time)
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
