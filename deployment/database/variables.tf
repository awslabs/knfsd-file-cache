/*
 * Copyright 2022 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

variable "VERSION" {
  description = "(Required) The version of the KNFSD File Cache."
  type        = string
  nullable    = false
  default     = "1.1.0-alpha.5"
  validation {
    condition     = can(regex("^(?P<major>0|[1-9]\\d*)\\.(?P<minor>0|[1-9]\\d*)\\.(?P<patch>0|[1-9]\\d*)(?:-(?P<prerelease>(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$", var.VERSION))
    error_message = "VERSION must be a valid semantic version 2.0.0 format. Example: \"1.1.0-alpha.5\"."
  }
}

variable "SUBNET" {
  description = "(Required) The subnet ID to use for deployment of the Amazon RDS DB instance. Example: \"subnet-038e337f0ff4cd53f\". No default."
  type        = string
  nullable    = false

  validation {
    condition     = var.SUBNET != "" && can(regex("^subnet-[a-z0-9]{8,17}$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "FSID_DB_SUBNET_GROUP_NAME" {
  description = "(Optional) The name of the Amazon RDS DB subnet group to use for the FSID database. Required when using a non-default VPC. Default: \"null\"."
  type        = string
  nullable    = true
  default     = null
}

variable "NAME_PREFIX" {
  description = "(Optional) Prefix to use when generating a RDS DB instance name. The name will be suffixed with a hyphen and 8 random letters/digits. Default: \"fsids\"."
  type        = string
  nullable    = false
  default     = "fsids"
}

variable "NAME" {
  description = "(Optional) The name of the RDS DB instance. If the name is left blank a random name will be generated based on \"NAME_PREFIX\". The name must be unique across all DB instances owned by your AWS account in the current AWS Region. Default: \"\"."
  type        = string
  default     = ""

  validation {
    condition = var.NAME == "" || (
      can(regex("^[a-z][a-z0-9-]{0,58}[a-z0-9]$", var.NAME)) && !can(regex("--", var.NAME))
    )
    error_message = "Name must be lowercase, 1-60 alphanumeric characters or hyphens. Must start with a letter, can't contain two consecutive hyphens, and can't end with a hyphen."
  }
}

variable "INSTANCE_CLASS" {
  description = "(Optional) The EC2 instance type to use. Must be a supported RDS PostgreSQL instance class. Default: \"db.t4g.medium\"."
  type        = string
  nullable    = false
  default     = "db.t4g.medium"

  validation {
    condition     = can(regex("^db\\.", var.INSTANCE_CLASS))
    error_message = "INSTANCE_CLASS must start with \"db.\". For example: \"db.t4g.medium\"."
  }
}

variable "DELETION_PROTECTION" {
  description = "(Optional) Whether or not to allow Terraform to destroy the instance. Unless this field is set to false in Terraform state, a \"terraform destroy\" or \"terraform apply\" command that deletes the instance will fail. Default: \"true\"."
  type        = bool
  nullable    = false
  default     = true
}

variable "ENABLE_PUBLIC_IP" {
  description = "(Optional) Whether to deploy the database with a public IP address. When the DB instance is publicly accessible and you connect from outside of the DB instance's Virtual Private Cloud (VPC), its Domain Name System (DNS) endpoint resolves to the public IP address. When you connect from within the same VPC as the DB instance, the endpoint resolves to the private IP address. Access to the DB instance is ultimately controlled by the EC2 security group it uses. Public access isn't permitted if the security group assigned to the DB instance doesn't permit it. When the DB instance isn't publicly accessible, it is an internal DB instance with a DNS name that resolves to a private IP address. Default: \"false\"."
  type        = bool
  nullable    = false
  default     = false
}

variable "MASTER_USERNAME" {
  description = "(Optional) The master username for the database. Password is stored in AWS Secrets Manager. Default: \"postgres\"."
  type        = string
  nullable    = false
  default     = "postgres"
}

variable "ASSUME_ROLE_ARN" {
  description = "(Optional) The ARN of the IAM role to assume for AWS CLI commands in local-exec provisioners for CI/CD pipelines. If not provided, no role assumption will be performed and the local-exec provisioner will use the existing AWS credentials from the environment. Example: \"arn:aws:iam::123456789012:role/DeploymentRole\". Default: \"null\"."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition = var.ASSUME_ROLE_ARN == null || (
      var.ASSUME_ROLE_ARN != "" && can(regex("^arn:aws:iam::[0-9]{12}:role/[a-zA-Z0-9+=,.@_-]+$", var.ASSUME_ROLE_ARN))
    )
    error_message = "When provided, ASSUME_ROLE_ARN must be a valid IAM role ARN format. Example: \"arn:aws:iam::123456789012:role/DeploymentRole\"."
  }
}
