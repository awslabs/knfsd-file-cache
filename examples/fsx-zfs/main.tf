# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/examples/fsx-zfs/1.1.0-beta.1"
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

locals {
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
}

# create FSx for OpenZFS as source filer
resource "aws_fsx_openzfs_file_system" "zfs" {
  deployment_type                 = "SINGLE_AZ_1"
  storage_capacity                = var.FSX_STORAGE_CAPACITY
  subnet_ids                      = [var.SUBNET]
  throughput_capacity             = var.FSX_THROUGHPUT_CAPACITY
  automatic_backup_retention_days = 0
  copy_tags_to_volumes            = true
  delete_options                  = ["DELETE_CHILD_VOLUMES_AND_SNAPSHOTS"]
  security_group_ids              = [aws_security_group.fsx_sg.id]
  skip_final_backup               = true
  storage_type                    = "SSD"

  root_volume_configuration {
    nfs_exports {
      client_configurations {
        clients = "*"
        options = ["rw", "crossmnt", "async", "no_root_squash"]
      }
    }
    copy_tags_to_snapshots = true
    data_compression_type  = "NONE"
  }

  tags = { "knfsd-file-cache:examples" = "fsx-zfs" }
}

# create a dedicated SG for FSx for OpenZFS
resource "aws_security_group" "fsx_sg" {
  name        = "fsx-zfs-sg"
  description = "knfsd security group for FSx ZFS"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow inbound NFS from the VPC CIDR block"
  }

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow inbound NFS over UDP (some NFS implementations may use UDP)"
  }

  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow inbound portmapper/rpcbind"
  }

  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow inbound portmapper/rpcbind"
  }

  ingress {
    from_port   = 20001
    to_port     = 20003
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow inbound TCP for OpenZFS management: NFS mount, status monitor, and lock daemon"
  }

  ingress {
    from_port   = 20001
    to_port     = 20003
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow inbound UDP for OpenZFS management: NFS mount, status monitor, and lock daemon"
  }

  tags = {
    "Name"                      = "fsx-zfs-sg",
    "knfsd-file-cache:examples" = "fsx-zfs"
  }
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

# Validate INSTANCE_TYPE is offered in selected subnet.
# tflint-ignore: terraform_unused_declarations
data "aws_ec2_instance_type_offerings" "instance_offered" {
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

module "proxy" {
  source                  = "../../deployment/terraform-module-knfsd"
  SUBNET                  = var.SUBNET
  KNFSD_NODES             = var.KNFSD_NODES
  PROXY_AMI               = var.PROXY_AMI
  INSTANCE_TAGS           = { "knfsd-file-cache:examples" = "fsx-zfs" }
  PROXY_BASENAME          = var.PROXY_BASENAME
  TRAFFIC_MODE            = var.TRAFFIC_MODE
  KEY_NAME                = var.KEY_NAME
  INSTANCE_TYPE           = var.INSTANCE_TYPE
  NUM_NFS_THREADS         = var.NUM_NFS_THREADS
  FSID_MODE               = var.FSID_MODE
  EXPORT_HOST_AUTO_DETECT = aws_fsx_openzfs_file_system.zfs.dns_name # Detect exports from the source filer via "showmount -e <SOURCE_FILER_DNS_NAME>"
  EXPORT_OPTIONS          = "insecure"                               # Override the default "secure" option with "insecure" (required for "showmount" auto-discovery by clients)
  NFS_MOUNT_VERSION       = "3"                                      # Mount the source filer as NFSv3
  DISABLED_NFS_VERSIONS   = "4.0,4.1,4.2"                            # Ensure NFS v3 is used ("showmount" auto-discovery)
  depends_on = [
    data.aws_ami.proxy_exists,      # Ensure proxy AMI exists
    data.aws_ami.proxy_arch,        # Ensure proxy AMI architecture matches instance type
    aws_fsx_openzfs_file_system.zfs # Ensure FSx for OpenZFS is created before deploying the proxy
  ]
}
