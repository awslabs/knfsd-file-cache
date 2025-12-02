/*
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
  # A 4th argument can be provided to the EXPORT_MAP variable
  # to identify the <FILESYSTEM_TYPE> as "efs" to force the
  # "mount.efs" helper to be used.
  # <SOURCE_DNS>;<SOURCE_EXPORT>;<TARGET_EXPORT>;<FILESYSTEM_TYPE>
  export_map     = "${aws_efs_mount_target.efs_mt.dns_name};/;/efs;efs"
  az             = data.aws_subnet.selected.availability_zone
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
}

# create EFS as source filer
# nosemgrep: aws-efs-filesystem-encrypted-with-cmk
resource "aws_efs_file_system" "efs" {
  availability_zone_name = local.az
  creation_token         = "knfsd-file-cache-efs"
  encrypted              = true
  performance_mode       = "generalPurpose"
  throughput_mode        = "bursting"
  tags                   = { "knfsd-file-cache:examples" = "efs" }
}

# disable EFS backup policy to save cost
resource "aws_efs_backup_policy" "efs_backup_policy" {
  file_system_id = aws_efs_file_system.efs.id
  backup_policy {
    status = "DISABLED"
  }
}

# create a dedicated SG for the EFS mount target
resource "aws_security_group" "efs_mt_sg" {
  name        = "efs-mt-sg"
  description = "knfsd security group for EFS mount target"
  vpc_id      = data.aws_subnet.selected.vpc_id

  # allow inbound NFS from the proxy ASG security group
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.proxy.autoscaling_group_security_group_id]
    description     = "Allow NFS from proxy ASG"
  }

  # default egress rule: allow all outbound traffic to VPC
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow all outbound traffic to VPC"
  }

  tags = {
    "Name"                      = "efs-mt-sg",
    "knfsd-file-cache:examples" = "efs"
  }
}

resource "aws_efs_mount_target" "efs_mt" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = var.SUBNET
  security_groups = [aws_security_group.efs_mt_sg.id]
}

# Validate that the proxy AMI exists and is accessible.
# tflint-ignore: terraform_unused_declarations
data "aws_ami" "proxy_exists" {
  filter {
    name   = "image-id"
    values = [var.PROXY_AMI]
  }
}

# Validate AMI architecture matches instance type before deployment.
# tflint-ignore: terraform_unused_declarations
data "aws_ami" "proxy_arch" {
  filter {
    name   = "image-id"
    values = [var.PROXY_AMI]
  }

  lifecycle {
    postcondition {
      condition = (
        can(regex("^[a-z]+[0-9]g[a-z]*\\.", var.INSTANCE_TYPE))
        ? self.architecture == "arm64"
        : self.architecture == "x86_64"
      )
      error_message = "PROXY_AMI architecture (${self.architecture}) does not match INSTANCE_TYPE (${var.INSTANCE_TYPE}) architecture."
    }
  }
}

module "proxy" {
  source                = "../../deployment/terraform-module-knfsd"
  SUBNET                = var.SUBNET
  KNFSD_NODES           = var.KNFSD_NODES
  PROXY_AMI             = var.PROXY_AMI
  PROXY_BASENAME        = var.PROXY_BASENAME
  TRAFFIC_MODE          = "dns_round_robin"
  KEY_NAME              = var.KEY_NAME
  FSID_MODE             = "static" # this should not be used in production or with more than a single node
  INSTANCE_TYPE         = var.INSTANCE_TYPE
  EXPORT_MAP            = local.export_map
  NFS_MOUNT_VERSION     = "4.1"       # EFS only supports NFS v4.1
  DISABLED_NFS_VERSIONS = "3,4.0,4.2" # EFS only supports NFS v4.1
  MOUNT_OPTIONS         = "noresvport"
  INSTANCE_TAGS         = { "knfsd-file-cache:examples" = "efs" }
  depends_on = [
    data.aws_ami.proxy_exists, # Ensure proxy AMI exists
    data.aws_ami.proxy_arch    # Ensure proxy AMI architecture matches instance type
  ]
}
