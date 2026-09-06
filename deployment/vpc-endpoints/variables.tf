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

variable "REGION" {
  description = "(Required) The AWS region for the deployment. Example: \"us-east-1\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.REGION))
    error_message = "REGION must be a valid AWS region format. Example: \"us-east-1\"."
  }
}

variable "SUBNETS" {
  description = "(Required) One or more AWS Subnet IDs to use for deployment of the VPC interface endpoints. Each interface endpoint is created across every listed subnet (one ENI per subnet/AZ). The DynamoDB gateway endpoint is not subnet-scoped and is associated with the route tables governing these subnets. No default."
  type        = list(string)
  nullable    = false
  validation {
    condition     = length(var.SUBNETS) > 0
    error_message = "SUBNETS must contain at least one AWS Subnet ID."
  }
  validation {
    condition     = alltrue([for s in var.SUBNETS : can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", s))])
    error_message = "Each entry in SUBNETS must be a valid AWS Subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
  validation {
    condition     = length(var.SUBNETS) == length(distinct(var.SUBNETS))
    error_message = "SUBNETS must not contain duplicate Subnet IDs."
  }
}

variable "EXISTING_SECURITY_GROUP_ID" {
  description = "(Optional) ID of a pre-existing security group to attach to the KNFSD interface VPC endpoints instead of creating one. When set, the module skips creating the security group and all of its ingress/egress rules; you are responsible for configuring the required HTTPS (443) ingress from the VPC CIDR on the provided security group. Required when the deploying role lacks ec2:CreateSecurityGroup. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.EXISTING_SECURITY_GROUP_ID == "" || can(regex("^sg-[0-9a-f]{8,17}$", var.EXISTING_SECURITY_GROUP_ID))
    error_message = "When provided, EXISTING_SECURITY_GROUP_ID must be a valid AWS security group ID format. Example: \"sg-0123456789abcdef0\"."
  }
}
