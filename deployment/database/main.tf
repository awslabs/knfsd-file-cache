# Copyright 2022 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.63.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/database/1.1.0-beta.3"
    ]
  }
}

# generate a random name for the DynamoDB table
# example: "knfsd-fsids-a1b2c3d4"
resource "random_id" "name" {
  prefix      = "${var.NAME_PREFIX}-"
  byte_length = 4
  keepers = {
    region = local.region
  }
}

# get the current AWS region
data "aws_region" "current" {}

# local variables
locals {
  tags   = { "knfsd-file-cache:version" = var.VERSION }
  name   = coalesce(var.NAME, random_id.name.hex)
  region = data.aws_region.current.region

  # When NAME is provided (e.g. terraform-module-knfsd passes the cluster
  # name) suffix it with "-fsids" so the table is self-describing
  # (e.g. "mycluster-fsids"). When NAME is left blank the random default
  # already carries the "knfsd-fsids" NAME_PREFIX, so no suffix is needed
  # (e.g. "knfsd-fsids-a1b2c3d4").
  table_name = var.NAME != "" ? "${var.NAME}-fsids" : random_id.name.hex

  # Use the custom IAM policy for DynamoDB access when provided,
  # otherwise the one created by this module
  db_iam_policy_arn = var.FSID_DATABASE_IAM_POLICY != "" ? var.FSID_DATABASE_IAM_POLICY : aws_iam_policy.db_policy[0].arn
}

# DynamoDB table storing the FSID mappings.
# See README.md for the full item/key design (PATH#, FSID#, COUNTER items).
# The knfsd-fsidd daemon addresses the table by (region, table name); the
# table ARN is the canonical unique identifier for reuse across deployments.
# A KMS CMK is unnecessary: the table holds non-sensitive path<->fsid
# mappings and SSE with the AWS managed key (aws/dynamodb) is sufficient.
# nosemgrep: aws-dynamodb-table-unencrypted
resource "aws_dynamodb_table" "fsids" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # encryption at rest with the AWS managed key (aws/dynamodb)
  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = var.DELETION_PROTECTION

  tags = merge(local.tags, { Name = local.table_name })
}

# IAM default policy for DynamoDB table access (referenced by
# "terraform-module-knfsd/iam.tf" via "database/outputs.tf").
# Least privilege: only the item-level actions used by knfsd-fsidd, scoped to
# this table only. TransactWriteItems authorizes via the underlying item
# actions (PutItem, UpdateItem, ConditionCheckItem).
# Skipped when FSID_DATABASE_IAM_POLICY is set; the table is still
# deployed and the provided policy ARN flows through the output.
resource "aws_iam_policy" "db_policy" {
  count  = var.FSID_DATABASE_IAM_POLICY == "" ? 1 : 0
  name   = "${local.name}-dynamodb-auth-policy"
  policy = data.aws_iam_policy_document.db_role_document.json
  tags   = local.tags
}

# IAM default policy document to allow DynamoDB table access
data "aws_iam_policy_document" "db_role_document" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:ConditionCheckItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.fsids.arn]
  }
}

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
