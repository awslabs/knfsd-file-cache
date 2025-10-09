/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.15.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
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
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
}

# generate a cryptographically secure password for "fsxadmin" user
# WARNING: for production workloads, password should be generated and stored outside of Terraform state file
resource "random_password" "fsxadmin_password" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*()_+"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

# AWS Secrets Manager secret for fsxadmin password
# nosemgrep: aws-secretsmanager-secret-unencrypted
resource "aws_secretsmanager_secret" "fsxadmin_password" {
  name                    = "${var.PROXY_BASENAME}-fsxadmin-password"
  description             = "FSx for NetApp ONTAP fsxadmin password"
  recovery_window_in_days = 0
  tags                    = { "knfsd-file-cache:examples" = "fsx-netapp" }
}

# store the fsxadmin password in the secret
resource "aws_secretsmanager_secret_version" "fsxadmin_password" {
  secret_id = aws_secretsmanager_secret.fsxadmin_password.id
  secret_string = jsonencode({
    secret = random_password.fsxadmin_password.result
  })
}

# create FSx for NetApp ONTAP as source filer
# nosemgrep: aws-fsx-ontapfs-encrypted-with-cmk
resource "aws_fsx_ontap_file_system" "ontap" {
  deployment_type                 = "SINGLE_AZ_1"
  storage_capacity                = 2560 # Total storage capacity 2.5TB (5 volumes x 500GB each)
  subnet_ids                      = [var.SUBNET]
  preferred_subnet_id             = var.SUBNET
  throughput_capacity             = 128
  automatic_backup_retention_days = 0
  security_group_ids              = [aws_security_group.fsx_sg.id]
  fsx_admin_password              = random_password.fsxadmin_password.result
  tags                            = { "knfsd-file-cache:examples" = "fsx-netapp" }
}

# create Storage Virtual Machine (SVM)
resource "aws_fsx_ontap_storage_virtual_machine" "svm" {
  file_system_id = aws_fsx_ontap_file_system.ontap.id
  name           = "svm01"
  tags           = { "knfsd-file-cache:examples" = "fsx-netapp" }
}

# create volume 1 (500GB)
resource "aws_fsx_ontap_volume" "volume1" {
  junction_path              = "/vol1"
  name                       = "vol1"
  size_in_megabytes          = 512000 # 500GB in MB
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.svm.id
  storage_efficiency_enabled = true
  skip_final_backup          = true
  tiering_policy { name = "NONE" }
  tags = { "knfsd-file-cache:examples" = "fsx-netapp" }
}

# create volume 2 (500GB) - junction point under volume 1
resource "aws_fsx_ontap_volume" "volume2" {
  junction_path              = "/vol1/vol2" # Junction point under vol1
  name                       = "vol2"
  size_in_megabytes          = 512000 # 500GB in MB
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.svm.id
  storage_efficiency_enabled = true
  skip_final_backup          = true
  tiering_policy { name = "NONE" }
  tags       = { "knfsd-file-cache:examples" = "fsx-netapp" }
  depends_on = [aws_fsx_ontap_volume.volume1]
}

# create volume 3 (500GB)
resource "aws_fsx_ontap_volume" "volume3" {
  junction_path              = "/vol3"
  name                       = "vol3"
  size_in_megabytes          = 512000 # 500GB in MB
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.svm.id
  storage_efficiency_enabled = true
  skip_final_backup          = true
  tiering_policy { name = "NONE" }
  tags = { "knfsd-file-cache:examples" = "fsx-netapp" }
}

# create volume 4 (500GB) - nested under vol3
resource "aws_fsx_ontap_volume" "volume4" {
  junction_path              = "/vol3/vol4" # Junction point under vol3
  name                       = "vol4"
  size_in_megabytes          = 512000 # 500GB in MB
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.svm.id
  storage_efficiency_enabled = true
  skip_final_backup          = true
  tiering_policy { name = "NONE" }
  tags       = { "knfsd-file-cache:examples" = "fsx-netapp" }
  depends_on = [aws_fsx_ontap_volume.volume3]
}

# create volume 5 (500GB) - nested under vol3/vol4
resource "aws_fsx_ontap_volume" "volume5" {
  junction_path              = "/vol3/vol4/vol5" # Junction point under vol3/vol4
  name                       = "vol5"
  size_in_megabytes          = 512000 # 500GB in MB
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.svm.id
  storage_efficiency_enabled = true
  skip_final_backup          = true
  tiering_policy { name = "NONE" }
  tags       = { "knfsd-file-cache:examples" = "fsx-netapp" }
  depends_on = [aws_fsx_ontap_volume.volume4]
}

# GET the AWS FSx certificate bundle for the specific AWS region
data "http" "aws_ca_bundle" {
  url = "https://fsx-aws-certificates.s3.amazonaws.com/bundle-${var.REGION}.pem"
  retry {
    attempts     = 2
    min_delay_ms = 2000
    max_delay_ms = 8000
  }
}

# create a dedicated SG for FSx for NetApp ONTAP
resource "aws_security_group" "fsx_sg" {
  name        = "fsx-netapp-sg"
  description = "knfsd security group for FSx NetApp ONTAP"
  vpc_id      = data.aws_subnet.selected.vpc_id

  # TCP 2049 - NFS server daemon
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow NFS TCP from proxy ASG"
  }

  # UDP 2049 - NFS server daemon
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow NFS UDP from proxy ASG"
  }

  # TCP 111 - Remote procedure call for NFS
  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow portmapper TCP from proxy ASG"
  }

  # UDP 111 - Remote procedure call for NFS
  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow portmapper UDP from proxy ASG"
  }

  # TCP 443 - ONTAP REST API access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow HTTPS for NetApp ONTAP REST API from proxy ASG"
  }

  # ICMP - Pinging the instance
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow ICMP for pinging the instance from proxy ASG"
  }

  # TCP 161-162 - Simple network management protocol (SNMP)
  ingress {
    from_port   = 161
    to_port     = 162
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow TCP SNMP from proxy ASG"
  }

  # TCP 635 - NFS mount
  ingress {
    from_port   = 635
    to_port     = 635
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow TCP NFS mount from proxy ASG"
  }

  # UDP 635 - NFS mount
  ingress {
    from_port   = 635
    to_port     = 635
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow UDP NFS mount from proxy ASG"
  }

  # TCP 4045 - NFS lock daemon
  ingress {
    from_port   = 4045
    to_port     = 4045
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow TCP NFS lock daemon from proxy ASG"
  }

  # UDP 4045 - NFS lock daemon
  ingress {
    from_port   = 4045
    to_port     = 4045
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow UDP NFS lock daemon from proxy ASG"
  }

  # TCP 4046 - Network status monitor for NFS
  ingress {
    from_port   = 4046
    to_port     = 4046
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow TCP network status monitor for NFS from proxy ASG"
  }

  # UDP 4046 - Network status monitor for NFS
  ingress {
    from_port   = 4046
    to_port     = 4046
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow UDP network status monitor for NFS from proxy ASG"
  }

  # UDP 4049 - NFS quota protocol
  ingress {
    from_port   = 4049
    to_port     = 4049
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow UDP NFS quota protocol from proxy ASG"
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
    "Name"                      = "fsx-netapp-sg",
    "knfsd-file-cache:examples" = "fsx-netapp"
  }
}

# wait for all FSx NetApp ONTAP resources to be ready before deploying the KNFSD proxy
resource "null_resource" "fsx_netapp_ready" {
  depends_on = [
    aws_fsx_ontap_file_system.ontap,
    aws_fsx_ontap_storage_virtual_machine.svm,
    aws_fsx_ontap_volume.volume1,
    aws_fsx_ontap_volume.volume2,
    aws_fsx_ontap_volume.volume3,
    aws_fsx_ontap_volume.volume4,
    aws_fsx_ontap_volume.volume5
  ]
}

# deploy the proxy
module "proxy" {
  source                    = "../../deployment/terraform-module-knfsd"
  SUBNET                    = var.SUBNET
  KNFSD_NODES               = 1
  PROXY_AMI                 = var.PROXY_AMI
  PROXY_BASENAME            = var.PROXY_BASENAME
  TRAFFIC_MODE              = "dns_round_robin"
  KEY_NAME                  = var.KEY_NAME
  FSID_MODE                 = "external"
  INSTANCE_TAGS             = { "knfsd-file-cache:examples" = "fsx-netapp" }
  ENABLE_NETAPP_AUTO_DETECT = true                                                                                     # Enable automatic detection of NetApp exports
  NETAPP_HOST               = aws_fsx_ontap_storage_virtual_machine.svm.endpoints[0].nfs[0].dns_name                   # NetApp NFS SVM dns name
  NETAPP_URL                = "https://${aws_fsx_ontap_file_system.ontap.endpoints[0].management[0].dns_name}/api/v1/" # NetApp ONTAP REST API endpoint URL
  NETAPP_USER               = "fsxadmin"                                                                               # Username for NetApp ONTAP API authentication
  NETAPP_SECRET             = aws_secretsmanager_secret.fsxadmin_password.name                                         # AWS Secrets Manager secret name containing NetApp credentials
  NETAPP_SECRET_REGION      = var.REGION                                                                               # AWS region where the NetApp secret is stored
  NETAPP_SECRET_VERSION     = "AWSCURRENT"                                                                             # Version of the secret to retrieve
  NETAPP_CA                 = data.http.aws_ca_bundle.response_body                                                    # Certificate authority bundle for NetApp TLS verification
  NETAPP_ALLOW_COMMON_NAME  = false                                                                                    # Allow certificate common name validation (not required for FSx NetApp ONTAP)
  EXCLUDED_EXPORTS          = ["/"]                                                                                    # Exclude the root "/" export (svm01_root)
  NFS_MOUNT_VERSION         = "4.1"                                                                                    # Use NFSv4.1 (larger filehandle size)
  DISABLED_NFS_VERSIONS     = "3,4.0,4.2"                                                                              # Only allow NFSv4.1 on exports for consistency
  depends_on                = [null_resource.fsx_netapp_ready]                                                         # Wait for FSx NetApp ONTAP to be ready before deploying the KNFSD proxy
}
