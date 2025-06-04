/*
 * Copyright 2020 Google Inc.
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

provider "aws" {
  region = var.REGION
  default_tags {
    tags = {
      "knfsd-file-cache:version" = var.VERSION
    }
  }
}

# generate a random name for the knfsd cluster
# example: "nfsproxy-a1b2c3d4"
resource "random_id" "name" {
  prefix      = "${var.PROXY_BASENAME}-"
  byte_length = 4
  keepers = {
    region = var.REGION,
    subnet = var.SUBNET
  }
}

# get the default, provider tags
data "aws_default_tags" "current" {}

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
  az                   = data.aws_subnet.selected.availability_zone
  vpc_id               = data.aws_vpc.selected.id
  vpc_cidr_block       = data.aws_vpc.selected.cidr_block
  name                 = var.PROXY_BASENAME != "nfsproxy" ? var.PROXY_BASENAME : random_id.name.hex
  asg_name             = "${local.name}-asg"
  asg_tags             = merge(data.aws_default_tags.current.tags, var.INSTANCE_TAGS)
  deploy_fsid_database = var.FSID_MODE == "external" && var.FSID_DATABASE_DEPLOY
  custom_fsid_database = (
    var.FSID_MODE == "external" &&
    var.FSID_DATABASE_DEPLOY == false &&
    var.FSID_DATABASE_CONFIG != "" &&
    var.FSID_DATABASE_IAM_POLICY != ""
  )
}

module "fsid_database" {
  source                    = "../database"
  count                     = local.deploy_fsid_database ? 1 : 0
  REGION                    = var.REGION
  SUBNET                    = var.SUBNET
  FSID_DB_SUBNET_GROUP_NAME = var.FSID_DB_SUBNET_GROUP_NAME
  NAME                      = "${local.name}-fsids"
  DELETION_PROTECTION       = false
}
