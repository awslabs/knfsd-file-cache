# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Smoke-test infrastructure: source NFS EC2 instance, single-node KNFSD proxy
# ASG, and a single test client EC2 instance, all running in an existing VPC
# (an existing or default VPC subnet supplied via var.SUBNET). The source-NFS
# and client security groups are self-created from the subnet's VPC CIDR.
# SSH/SCP access for the Go test driver is keyless: the driver tunnels over SSM
# (AWS-StartSSHSession) and pushes an ephemeral key via EC2 Instance Connect at
# connect time, so no SSH key pair is created or stored.
#
# The deployment is wired from three modules:
#   - source-nfs : the upstream NFS filer (modules/source-nfs)
#   - proxy      : the KNFSD proxy ASG (deployment/terraform-module-knfsd)
#   - nfs-client : the test client running remote.test (modules/nfs-client)

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/image/smoke-tests/1.1.0-alpha.27"
    ]
  }
}

provider "aws" {
  region = var.REGION
}

data "aws_subnet" "selected" {
  id = var.SUBNET
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

module "source_nfs" {
  source                      = "../modules/source-nfs"
  REGION                      = var.REGION
  NAME                        = "${var.PREFIX}-source"
  SUBNET                      = var.SUBNET
  SECURITY_GROUP_ID           = aws_security_group.source_nfs.id
  ASSOCIATE_PUBLIC_IP_ADDRESS = var.ASSOCIATE_PUBLIC_IP_ADDRESS
  TAGS = {
    "knfsd-file-cache:run" = var.PREFIX
  }
}

module "proxy" {
  source                      = "../../../deployment/terraform-module-knfsd"
  SUBNET                      = var.SUBNET
  TRAFFIC_MODE                = "dns_round_robin"
  PROXY_BASENAME              = "${var.PREFIX}-proxy"
  PROXY_AMI                   = var.PROXY_AMI
  KNFSD_NODES                 = 1
  EXPORT_MAP                  = "${module.source_nfs.private_ip};/files;/files"
  FSID_MODE                   = "static"
  ENABLE_STATUS_CHECK         = true
  ASSOCIATE_PUBLIC_IP_ADDRESS = var.ASSOCIATE_PUBLIC_IP_ADDRESS
}

module "nfs_client" {
  source                      = "../modules/nfs-client"
  REGION                      = var.REGION
  SUBNET                      = var.SUBNET
  SECURITY_GROUP_ID           = aws_security_group.client.id
  PREFIX                      = var.PREFIX
  ARCH                        = var.ARCH
  INSTANCE_TYPE               = var.INSTANCE_TYPE
  ASSOCIATE_PUBLIC_IP_ADDRESS = var.ASSOCIATE_PUBLIC_IP_ADDRESS
  SOURCE_HOST                 = module.source_nfs.private_ip
  PROXY_HOST                  = module.proxy.dns_name
  CLUSTER_READY               = module.proxy.cluster_ready
}
