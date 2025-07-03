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
      version = "~> 6.2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7.1"
    }
  }
}

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
  tags = {
    "knfsd-file-cache:version" = var.VERSION
  }
}

# create a private route53 DNS zone for the dns-rr cluster
resource "aws_route53_zone" "nfsproxy" {
  count         = var.DNS_NAME == "" ? 1 : 0
  name          = "${var.PROXY_BASENAME}.aws.internal."
  comment       = "Internal DNS for KNFSD DNS Round-Robin"
  force_destroy = true
  vpc {
    vpc_id = data.aws_vpc.selected.id
  }
  tags = merge(local.tags, { Name = "${var.PROXY_BASENAME}.aws.internal" })
}
