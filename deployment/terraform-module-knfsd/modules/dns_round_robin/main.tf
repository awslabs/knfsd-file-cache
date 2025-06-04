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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7.0"
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
  dns_name = trimspace(coalesce(var.DNS_NAME, "${var.PROXY_BASENAME}.knfsd.internal."))
}

# create a private route53 DNS zone for the cluster
resource "aws_route53_zone" "nfsproxy" {
  name          = local.dns_name
  comment       = "Internal DNS for KNFSD proxies"
  force_destroy = true

  vpc {
    vpc_id = data.aws_vpc.selected.id
  }

  tags = {
    Name = trimsuffix(local.dns_name, ".")
  }
}
