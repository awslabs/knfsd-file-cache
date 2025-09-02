/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.11.0"
    }
  }
}

provider "aws" {
  region = var.REGION
}

################################################### PROJECTS ##################################################
# cluster: /projects
module "projects" {
  source = "../../deployment/terraform-module-knfsd"

  SUBNET = var.SUBNET

  INSTANCE_TAGS = { "knfsd-file-cache:examples" = "weka-projects" }

  INSTANCE_TYPE  = "i3en.6xlarge"
  PROXY_AMI      = var.PROXY_AMI
  PROXY_BASENAME = "projects"
  KNFSD_NODES    = 1 # set to 0 to disable cluster

  CUSTOM_PRE_STARTUP_SCRIPT = <<-EOF
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  EOF

  TRAFFIC_MODE = "dns_round_robin"
  DNS_NAME     = "projects.aws.internal."

  # metadata cache timeouts
  ACREGMIN = 300 # file inode min cache time
  ACREGMAX = 300 # file inode max cache time
  ACDIRMIN = 300 # directory min cache time
  ACDIRMAX = 300 # directory max cache time

  # NFS Settings
  FSID_MODE                 = "external"
  FSID_DB_SUBNET_GROUP_NAME = null # if using a non-default VPC, you must specify the name of the DB subnet group
  EXPORT_MAP                = "${var.WEKA_NFS_GATEWAY};/;/"
  NFS_MOUNT_VERSION         = "4.1"
  DISABLED_NFS_VERSIONS     = "3"
  AUTO_REEXPORT             = true
}

################################################### SOFTWARE ##################################################
# cluster: /software
module "software" {
  source = "../../deployment/terraform-module-knfsd"

  SUBNET = var.SUBNET

  INSTANCE_TAGS = { "knfsd-file-cache:examples" = "weka-software" }

  INSTANCE_TYPE  = "i3en.3xlarge"
  PROXY_AMI      = var.PROXY_AMI
  PROXY_BASENAME = "software"
  KNFSD_NODES    = 1 # set to 0 to disable cluster

  CUSTOM_PRE_STARTUP_SCRIPT = <<-EOF
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  EOF

  TRAFFIC_MODE = "dns_round_robin"
  DNS_NAME     = "software.aws.internal."

  # metadata cache timeouts
  ACREGMIN = 3600 # file inode min cache time
  ACREGMAX = 3600 # file inode max cache time
  ACDIRMIN = 3600 # directory min cache time
  ACDIRMAX = 3600 # directory max cache time

  # NFS Settings
  FSID_MODE                 = "external"
  FSID_DB_SUBNET_GROUP_NAME = null # if using a non-default VPC, you must specify the name of the DB subnet group
  EXPORT_MAP                = var.EXPORT_MAP_SOFTWARE
  # Set to v3 to improve software launch times, v4.x uses lookups when opening files back to source which cause slow startup times
  NFS_MOUNT_VERSION = "3"
  # Explicitly disabling unwanted NFS versions prevents clients from accidentally auto-negotiating an undesired NFS version
  # Force use of NFS v4.x only. Solves file handle issues
  DISABLED_NFS_VERSIONS = "3"
  AUTO_REEXPORT         = true
  MOUNT_OPTIONS         = "nolock"
}
