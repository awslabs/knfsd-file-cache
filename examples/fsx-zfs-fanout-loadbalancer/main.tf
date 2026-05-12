/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.44.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/examples/fsx-zfs-fanout-loadbalancer/1.1.0-alpha.26"
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

# create FSx for OpenZFS as source filer
resource "aws_fsx_openzfs_file_system" "zfs" {
  deployment_type                 = "SINGLE_AZ_1"
  storage_capacity                = 2048
  subnet_ids                      = [var.SUBNET]
  throughput_capacity             = 1024
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
        options = ["rw", "crossmnt", "async"]
      }
    }
    copy_tags_to_snapshots = true
    data_compression_type  = "NONE"
  }

  tags = { "knfsd-file-cache:examples" = "fsx-zfs-fanout-loadbalancer" }
}

# create a dedicated SG for FSx for OpenZFS
resource "aws_security_group" "fsx_sg" {
  name        = "fsx-zfs-sg"
  description = "knfsd security group for FSx ZFS"
  vpc_id      = data.aws_subnet.selected.vpc_id

  # allow inbound NFS from the proxy ASG security group
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.knfsd_fanout.autoscaling_group_security_group_id]
    description     = "Allow NFS TCP from proxy ASG"
  }

  # allow inbound NFS over UDP (some NFS implementations may use UDP)
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "udp"
    security_groups = [module.knfsd_fanout.autoscaling_group_security_group_id]
    description     = "Allow NFS UDP from proxy ASG"
  }

  # allow inbound portmapper/rpcbind
  ingress {
    from_port       = 111
    to_port         = 111
    protocol        = "tcp"
    security_groups = [module.knfsd_fanout.autoscaling_group_security_group_id]
    description     = "Allow portmapper TCP from proxy ASG"
  }

  ingress {
    from_port       = 111
    to_port         = 111
    protocol        = "udp"
    security_groups = [module.knfsd_fanout.autoscaling_group_security_group_id]
    description     = "Allow portmapper UDP from proxy ASG"
  }

  # allow inbound TCP for OpenZFS management: NFS mount, status monitor, and lock daemon
  ingress {
    from_port       = 20001
    to_port         = 20003
    protocol        = "tcp"
    security_groups = [module.knfsd_fanout.autoscaling_group_security_group_id]
    description     = "Allow ZFS management TCP from proxy ASG"
  }

  # allow inbound UDP for OpenZFS management: NFS mount, status monitor, and lock daemon
  ingress {
    from_port       = 20001
    to_port         = 20003
    protocol        = "udp"
    security_groups = [module.knfsd_fanout.autoscaling_group_security_group_id]
    description     = "Allow ZFS management UDP from proxy ASG"
  }

  tags = {
    "Name"                      = "fsx-zfs-sg",
    "knfsd-file-cache:examples" = "fsx-zfs-fanout-loadbalancer"
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

module "knfsd_fanout" {
  source                = "../../deployment/terraform-module-knfsd"
  SUBNET                = var.SUBNET
  TRAFFIC_MODE          = "loadbalancer"
  KEY_NAME              = var.KEY_NAME
  PROXY_AMI             = var.PROXY_AMI
  INSTANCE_TAGS         = { "knfsd-file-cache:examples" = "fsx-zfs-fanout-loadbalancer" }
  INSTANCE_TYPE         = var.INSTANCE_TYPE                                       # Use a higher CPU and Memory machine type to increase fanout performance
  KNFSD_NODES           = 1                                                       # Only deploy 1 node in the cluster because we want a single fanout node
  EXPORT_MAP            = "${aws_fsx_openzfs_file_system.zfs.dns_name};/fsx;/fsx" # FSx ZFS mount target
  PROXY_BASENAME        = "knfsd-fanout"                                          # Give this proxy a unique base name
  NFS_MOUNT_VERSION     = "4.1"                                                   # Use NFSv4.1 (larger filehandle size)
  DISABLED_NFS_VERSIONS = "3,4.0,4.2"                                             # Only allow NFSv4.1 on exports for consistency
  ENABLE_STATUS_CHECK   = true                                                    # Enable status check to hold the deployment until all EC2 instances are status:ready
  depends_on = [
    data.aws_ami.proxy_exists, # Ensure proxy AMI exists
    data.aws_ami.proxy_arch,   # Ensure proxy AMI architecture matches instance type
  ]
}

module "knfsd_cluster" {
  source                   = "../../deployment/terraform-module-knfsd"
  SUBNET                   = var.SUBNET
  TRAFFIC_MODE             = "loadbalancer"
  KEY_NAME                 = var.KEY_NAME
  PROXY_AMI                = var.PROXY_AMI
  INSTANCE_TAGS            = { "knfsd-file-cache:examples" = "fsx-zfs-fanout-loadbalancer" }
  FSID_DATABASE_DEPLOY     = false                                                     # Reuse the database from the fanout module
  FSID_DATABASE_CONFIG     = module.knfsd_fanout.database_config                       # Database configuration from the fanout module
  FSID_DATABASE_IAM_POLICY = module.knfsd_fanout.database_iam_policy                   # ARN of the IAM policy for rds-db:connect database access from the fanout module
  INSTANCE_TYPE            = "i3en.6xlarge"                                            # Use a smaller CPU and memory machine type as we have multiple nodes in the cluster
  KNFSD_NODES              = 3                                                         # Deploy >1 knfsd node for the performant based, temporary proxy nodes
  EXPORT_MAP               = "${module.knfsd_fanout.loadbalancer_ipaddress};/fsx;/fsx" # Re-export the export from the fanout proxy
  PROXY_BASENAME           = "knfsd-cluster"                                           # Give this cluster a unique base name
  NFS_MOUNT_VERSION        = "4.1"                                                     # Mount the fanout node as NFSv4.1 due to filehandle size limitations in NFSv3
  DISABLED_NFS_VERSIONS    = "3,4.0,4.2"                                               # Only allow NFSv4.1 on exports due to additional filehandle size
  depends_on               = [module.knfsd_fanout.cluster_ready]                       # Deploy after "knfsd_fanout" status is "ready" (TAG:knfsd-file-cache:status=ready)
}
