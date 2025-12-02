/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.23.0"
    }
  }
}

provider "aws" {
  region = var.REGION
}

module "proxy" {
  source                    = "../../deployment/terraform-module-knfsd"
  SUBNET                    = var.SUBNET
  KNFSD_NODES               = 3
  PROXY_AMI                 = var.PROXY_AMI
  PROXY_BASENAME            = var.PROXY_BASENAME
  TRAFFIC_MODE              = "dns_round_robin"
  KEY_NAME                  = var.KEY_NAME
  FSID_MODE                 = "external" # default is "external", but including here for clarity
  FSID_DB_SUBNET_GROUP_NAME = null       # if using a non-default VPC, you must specify the name of the DB subnet group
  EXPORT_MAP                = var.EXPORT_MAP
  INSTANCE_TAGS             = { "knfsd-file-cache:examples" = "nfs-standard" }
}
