# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.63.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/examples/basic/1.1.0-beta.3"
    ]
  }
}

provider "aws" {
  region = var.REGION
}

# Validate that the proxy AMI exists and is accessible.
# tflint-ignore: terraform_unused_declarations
data "aws_ami" "proxy_exists" {
  filter {
    name   = "image-id"
    values = [var.PROXY_AMI]
  }
}

module "proxy" {
  source         = "../../deployment/terraform-module-knfsd"
  SUBNET         = var.SUBNET
  PROXY_AMI      = var.PROXY_AMI
  EXPORT_MAP     = var.EXPORT_MAP
  PROXY_BASENAME = var.PROXY_BASENAME
  INSTANCE_TAGS  = { "knfsd-file-cache:examples" = "nfs-basic" }
  depends_on     = [data.aws_ami.proxy_exists]
}
