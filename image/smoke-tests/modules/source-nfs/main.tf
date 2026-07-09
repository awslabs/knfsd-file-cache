# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Source NFS server: an EC2 instance with local NVMe instance storage,
# formatted as XFS and exported via NFSv3/v4. The export is scoped to the
# VPC CIDR of the subnet the instance lives in.

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.53.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/image/smoke-tests/modules/source-nfs/1.1.0-alpha.29"
    ]
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

data "aws_ssm_parameter" "ubuntu_ami" {
  count = var.AMI_ID == "" ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/26.04/stable/current/${var.ARCH}/hvm/ebs-gp3/ami-id"
}

locals {
  ami_id      = var.AMI_ID == "" ? data.aws_ssm_parameter.ubuntu_ami[0].value : var.AMI_ID
  vpc_cidr    = data.aws_vpc.selected.cidr_block
  delay_value = var.LATENCY_MS == 0 ? "" : "${var.LATENCY_MS}ms"
  rate_value  = var.RATE_LIMIT_MBIT == 0 ? "" : "${var.RATE_LIMIT_MBIT}MBit"
  user_data   = templatefile("${path.module}/scripts/startup.sh", {})
}

# Validate server AMI architecture matches INSTANCE_TYPE family.
# tflint-ignore: terraform_unused_declarations
data "aws_ami" "server_arch" {
  filter {
    name   = "image-id"
    values = [local.ami_id]
  }

  lifecycle {
    postcondition {
      condition = (
        can(regex("^[a-z]+[0-9]g[a-z]*\\.", var.INSTANCE_TYPE))
        ? self.architecture == "arm64"
        : self.architecture == "x86_64"
      )
      error_message = "Server AMI architecture (${self.architecture}) does not match INSTANCE_TYPE (${var.INSTANCE_TYPE}) architecture."
    }
  }
}

# Validate INSTANCE_TYPE is offered in the selected subnet's availability zone.
# tflint-ignore: terraform_unused_declarations
data "aws_ec2_instance_type_offerings" "server_offered" {
  filter {
    name   = "instance-type"
    values = [var.INSTANCE_TYPE]
  }
  filter {
    name   = "location"
    values = [data.aws_subnet.selected.availability_zone]
  }
  location_type = "availability-zone"
  lifecycle {
    postcondition {
      condition     = contains(self.instance_types, var.INSTANCE_TYPE)
      error_message = "INSTANCE_TYPE \"${var.INSTANCE_TYPE}\" is not offered in the subnet's availability zone \"${data.aws_subnet.selected.availability_zone}\"."
    }
  }
}

resource "aws_instance" "source" {
  ami                         = local.ami_id
  instance_type               = var.INSTANCE_TYPE
  subnet_id                   = var.SUBNET
  vpc_security_group_ids      = [var.SECURITY_GROUP_ID]
  associate_public_ip_address = var.ASSOCIATE_PUBLIC_IP_ADDRESS
  monitoring                  = true
  ebs_optimized               = true
  iam_instance_profile        = aws_iam_instance_profile.source.name

  root_block_device {
    volume_size           = var.ROOT_VOLUME_SIZE_GB
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  user_data = local.user_data

  tags = merge(
    var.TAGS,
    {
      Name                         = var.NAME
      "knfsd-file-cache:component" = "source-nfs"
      "knfsd-file-cache:vpc-cidr"  = local.vpc_cidr
      "knfsd-file-cache:delay"     = local.delay_value
      "knfsd-file-cache:rate"      = local.rate_value
      "knfsd-file-cache:status"    = "starting"
    },
  )

  volume_tags = merge(
    var.TAGS,
    {
      Name                         = "${var.NAME}-root"
      "knfsd-file-cache:component" = "source-nfs"
    },
  )

  lifecycle {
    ignore_changes = [tags["knfsd-file-cache:status"]]
  }
}
