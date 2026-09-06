# Copyright 2020 Google Inc.
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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/terraform-module-knfsd/1.1.0-beta.3"
    ]
  }
}

# generate a random name for the knfsd cluster
# example: "knfsd-a1b2c3d4"
resource "random_id" "name" {
  prefix      = "${var.PROXY_BASENAME}-"
  byte_length = 4
  keepers = {
    region = local.region,
    subnet = var.SUBNET
  }
}

# get the selected subnet
data "aws_subnet" "selected" {
  id = var.SUBNET
}

# get the VPC via selected subnet
data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

# local variables
locals {
  tags = {
    "knfsd-file-cache:version" = var.VERSION
  }
  az                   = data.aws_subnet.selected.availability_zone
  region               = regex("^([a-z]{2}(?:-[a-z]+)+-[0-9]+)", local.az)[0]
  vpc_id               = data.aws_vpc.selected.id
  vpc_cidr             = length(var.VPC_CIDR) > 0 ? var.VPC_CIDR : [data.aws_vpc.selected.cidr_block]
  export_cidr          = length(var.EXPORT_CIDR) > 0 ? var.EXPORT_CIDR : local.vpc_cidr
  is_windows           = can(env("USERPROFILE"))
  name                 = var.PROXY_BASENAME != "knfsd" ? var.PROXY_BASENAME : random_id.name.hex
  asg_name             = "${local.name}-asg"
  asg_tags             = merge(local.tags, var.INSTANCE_TAGS)
  deploy_fsid_database = var.FSID_MODE == "external" && var.FSID_DATABASE_DEPLOY
  custom_fsid_database = var.FSID_MODE == "external" && var.FSID_DATABASE_DEPLOY == false
  fsid_database_config = (
    # this module deployed an external fsid database, so generate our own config
    local.deploy_fsid_database ? templatefile("${path.module}/resources/knfsd-fsidd.conf.tftpl", {
      table_name     = module.fsid_database[0].table_name,
      region         = module.fsid_database[0].region,
      enable_metrics = var.ENABLE_METRICS,
    }) :
    # if custom config is provided (JSON object), generate the custom config
    length(var.FSID_DATABASE_CONFIG) > 0 ? templatefile("${path.module}/resources/knfsd-fsidd.conf.tftpl", {
      table_name     = lookup(var.FSID_DATABASE_CONFIG, "table_name", ""),
      region         = lookup(var.FSID_DATABASE_CONFIG, "region", local.region),
      enable_metrics = lookup(var.FSID_DATABASE_CONFIG, "enable_metrics", true),
    }) :
    "" # default: empty string, skipped when FSID_MODE="static"|"local"
  )
}

module "fsid_database" {
  source                   = "../database"
  count                    = local.deploy_fsid_database ? 1 : 0
  NAME                     = local.name
  DELETION_PROTECTION      = false
  FSID_DATABASE_IAM_POLICY = var.FSID_DATABASE_IAM_POLICY
}

# this solution collects anonymous operational metrics to help AWS improve the quality of features of the solution
resource "aws_cloudformation_stack" "metrics_knfsd" {
  name          = "${local.name}-metrics-knfsd"
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
