# Copyright 2022 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "VERSION" {
  description = "(Required) The version of the KNFSD File Cache."
  type        = string
  nullable    = false
  default     = "1.1.0-beta.3"
  validation {
    condition     = can(regex("^(?P<major>0|[1-9]\\d*)\\.(?P<minor>0|[1-9]\\d*)\\.(?P<patch>0|[1-9]\\d*)(?:-(?P<prerelease>(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$", var.VERSION))
    error_message = "VERSION must be a valid semantic version 2.0.0 format. Example: \"1.1.0-beta.3\"."
  }
}

variable "NAME_PREFIX" {
  description = "(Optional) Prefix to use when generating a random DynamoDB table name (used when \"NAME\" is left blank). The prefix will be suffixed with a hyphen and 8 random letters/digits. Default: \"knfsd-fsids\"."
  type        = string
  nullable    = false
  default     = "knfsd-fsids"
}

variable "NAME" {
  description = "(Optional) The base name of the DynamoDB table. The table will be named \"<NAME>-fsids\". If the name is left blank a random table name will be generated based on \"NAME_PREFIX\". The table name must be unique within your AWS account in the current AWS Region. Default: \"\"."
  type        = string
  default     = ""

  validation {
    condition = var.NAME == "" || (
      can(regex("^[a-z][a-z0-9-]{0,58}[a-z0-9]$", var.NAME)) && !can(regex("--", var.NAME))
    )
    error_message = "Name must be lowercase, 1-60 alphanumeric characters or hyphens. Must start with a letter, can't contain two consecutive hyphens, and can't end with a hyphen."
  }
}

variable "DELETION_PROTECTION" {
  description = "(Optional) Whether or not to allow Terraform to destroy the DynamoDB table. Unless this field is set to false in Terraform state, a \"terraform destroy\" or \"terraform apply\" command that deletes the table will fail. Default: \"true\"."
  type        = bool
  nullable    = false
  default     = true
}

variable "FSID_DATABASE_IAM_POLICY" {
  description = "(Optional) ARN of a custom IAM policy granting DynamoDB item-level access to the FSID table. When set, the module still deploys the DynamoDB table but skips creating the \"aws_iam_policy\", using the provided policy ARN instead (required when the deploying role lacks iam:CreatePolicy). Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.FSID_DATABASE_IAM_POLICY == "" || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", var.FSID_DATABASE_IAM_POLICY))
    error_message = "When provided, FSID_DATABASE_IAM_POLICY must be a valid IAM policy ARN."
  }
}
