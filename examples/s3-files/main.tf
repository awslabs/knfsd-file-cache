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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/examples/s3-files/1.1.0-alpha.25"
    ]
  }
}

provider "aws" {
  region = var.REGION
}

# get the current account ID
data "aws_caller_identity" "current" {}

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
  account_id     = data.aws_caller_identity.current.account_id
  name           = var.PROXY_BASENAME != "knfsd" ? var.PROXY_BASENAME : random_id.name.hex
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
  # <SOURCE_IP/FILESYSTEM_ID/DNS_NAME>;<SOURCE_EXPORT>;<TARGET_EXPORT>;<FILESYSTEM_TYPE>
  export_map = "${aws_s3files_mount_target.s3files.file_system_id};/;/s3files;s3files"
}

# --------------------------------------------------------------------------
# S3 bucket (with versioning required by S3 Files)
# --------------------------------------------------------------------------

resource "random_id" "name" {
  prefix      = "${var.PROXY_BASENAME}-"
  byte_length = 4
  keepers = {
    region = var.REGION,
    subnet = var.SUBNET
  }
}

# nosemgrep: aws-s3-bucket-versioning-not-enabled
resource "aws_s3_bucket" "s3files" {
  #checkov:skip=CKV_AWS_18  server access logging target bucket is out of scope for a demo.
  #checkov:skip=CKV_AWS_144 cross-region replication is not applicable for a single-region demo.
  #checkov:skip=CKV_AWS_145 default SSE-S3 encryption is sufficient for a demo.
  #checkov:skip=CKV2_AWS_61 lifecycle rules are not required for an ephemeral demo bucket.
  #checkov:skip=CKV2_AWS_62 S3 Files service manages its own EventBridge rules for bucket change notifications.
  bucket = "${local.name}-s3files"
  tags   = { "knfsd-file-cache:examples" = "s3-files" }
  # Allow `terraform destroy` to remove the bucket even when it contains
  # objects and non-current versions/delete markers (versioning is required by
  # S3 Files). Do NOT use in production.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "s3files" {
  bucket = aws_s3_bucket.s3files.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access on the s3files bucket.
resource "aws_s3_bucket_public_access_block" "s3files" {
  bucket                  = aws_s3_bucket.s3files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------
# IAM role for S3 Files service (bucket access + EventBridge)
# --------------------------------------------------------------------------

resource "aws_iam_role" "s3files_service" {
  name        = "${local.name}-s3files-service-role"
  description = "IAM role for S3 Files service to access the S3 bucket and manage EventBridge rules"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowS3FilesAssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "elasticfilesystem.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:s3files:${var.REGION}:${local.account_id}:file-system/*"
        }
      }
    }]
  })

  tags = { "knfsd-file-cache:examples" = "s3-files" }
}

resource "aws_iam_role_policy" "s3files_service" {
  name = "${local.name}-s3files-service-policy"
  role = aws_iam_role.s3files_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketPermissions"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions",
        ]
        Resource = aws_s3_bucket.s3files.arn
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "S3ObjectPermissions"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject*",
          "s3:GetObject*",
          "s3:List*",
          "s3:PutObject*",
        ]
        Resource = "${aws_s3_bucket.s3files.arn}/*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "EventBridgeManage"
        Effect = "Allow"
        Action = [
          "events:DeleteRule",
          "events:DisableRule",
          "events:EnableRule",
          "events:PutRule",
          "events:PutTargets",
          "events:RemoveTargets",
        ]
        Condition = {
          StringEquals = {
            "events:ManagedBy" = "elasticfilesystem.amazonaws.com"
          }
        }
        Resource = ["arn:aws:events:*:*:rule/DO-NOT-DELETE-S3-Files*"]
      },
      {
        Sid    = "EventBridgeRead"
        Effect = "Allow"
        Action = [
          "events:DescribeRule",
          "events:ListRuleNamesByTarget",
          "events:ListRules",
          "events:ListTargetsByRule",
        ]
        Resource = ["arn:aws:events:*:*:rule/*"]
      },
    ]
  })
}

# --------------------------------------------------------------------------
# S3 Files filesystem
# --------------------------------------------------------------------------

resource "aws_s3files_file_system" "s3files" {
  bucket   = aws_s3_bucket.s3files.arn
  role_arn = aws_iam_role.s3files_service.arn
  tags     = { "knfsd-file-cache:examples" = "s3-files" }

  depends_on = [
    aws_s3_bucket_versioning.s3files,
    aws_iam_role_policy.s3files_service,
  ]
}

# --------------------------------------------------------------------------
# Synchronization configuration
# --------------------------------------------------------------------------

resource "aws_s3files_synchronization_configuration" "s3files" {
  file_system_id = aws_s3files_file_system.s3files.id

  import_data_rule {
    prefix         = ""
    size_less_than = 131072 # 128 KiB (default)
    trigger        = "ON_FILE_ACCESS"
  }

  expiration_data_rule {
    days_after_last_access = 30
  }
}

# --------------------------------------------------------------------------
# Security group for S3 Files mount target
# --------------------------------------------------------------------------

resource "aws_security_group" "s3files_mt_sg" {
  name        = "${local.name}-s3files-mt-sg"
  description = "knfsd security group for S3 Files mount target"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.proxy.autoscaling_group_security_group_id]
    description     = "Allow NFS from proxy ASG"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow all outbound traffic to VPC"
  }

  tags = {
    "Name"                      = "${local.name}-s3files-mt-sg"
    "knfsd-file-cache:examples" = "s3-files"
  }
}

# --------------------------------------------------------------------------
# S3 Files mount target (single-AZ, same subnet as KNFSD proxy)
# --------------------------------------------------------------------------

resource "aws_s3files_mount_target" "s3files" {
  file_system_id  = aws_s3files_file_system.s3files.id
  subnet_id       = var.SUBNET
  security_groups = [aws_security_group.s3files_mt_sg.id]
}

# --------------------------------------------------------------------------
# IAM policies for KNFSD proxy instances (S3 Files client access)
# --------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "proxy_s3files_client" {
  role       = module.proxy.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FilesClientFullAccess"
}

resource "aws_iam_role_policy_attachment" "proxy_efs_utils" {
  role       = module.proxy.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemsUtils"
}

resource "aws_iam_role_policy" "proxy_s3_read" {
  name = "${local.name}-s3files-s3-read-policy"
  role = module.proxy.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ObjectReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
        ]
        Resource = "${aws_s3_bucket.s3files.arn}/*"
      },
      {
        Sid      = "S3BucketListAccess"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.s3files.arn
      },
    ]
  })
}

# --------------------------------------------------------------------------
# Proxy AMI/INSTANCE_TYPE validation
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# KNFSD proxy module
# --------------------------------------------------------------------------

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
  NFS_MOUNT_VERSION     = "4.2"        # S3 Files supports NFS v4.1 and v4.2 (v4.2 default)
  DISABLED_NFS_VERSIONS = "3,4.0,4.1"  # enforce NFS v4.2 only
  MOUNT_OPTIONS         = "noresvport" # "nodirects3read" - disables direct S3 reads for files
  INSTANCE_TAGS         = { "knfsd-file-cache:examples" = "s3-files" }
  depends_on = [
    data.aws_ami.proxy_exists, # Ensure proxy AMI exists
    data.aws_ami.proxy_arch    # Ensure proxy AMI architecture matches instance type
  ]
}
