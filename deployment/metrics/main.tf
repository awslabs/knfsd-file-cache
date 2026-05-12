/*
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.44.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/metrics/1.1.0-alpha.26"
    ]
  }
}

locals {
  dashboard_name = "KNFSD-File-Cache-v${var.VERSION}"
}

resource "aws_cloudwatch_dashboard" "knfsd_monitoring_dashboard" {
  dashboard_name = local.dashboard_name
  dashboard_body = file("${path.module}/dashboard/dashboard.json")
}

# this solution collects anonymous operational metrics to help AWS improve the quality of features of the solution
resource "aws_cloudformation_stack" "metrics_dashboard" {
  name          = "knfsd-metrics-dashboard"
  on_failure    = "DO_NOTHING"
  template_body = <<STACK
    {
        "AWSTemplateFormatVersion": "2010-09-09",
        "Description": "(SO9129) - KNFSD-File-Cache Dashboard v${var.VERSION}",
        "Resources": {
            "EmptyResource": {
                "Type": "AWS::CloudFormation::WaitConditionHandle"
            }
        }
    }
    STACK
}
