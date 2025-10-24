/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

variable "REGION" {
  description = "(Required) The AWS region to use for deployment of the KNFSD File Cache. Example: \"us-east-1\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9]$", var.REGION))
    error_message = "REGION must be a valid AWS region format. Example: \"us-east-1\"."
  }
}

variable "SUBNET" {
  description = "(Required) The single subnet ID to use for deployment of the FSx for OpenZFS source filer and KNFSD File Cache. Example: \"subnet-038e337f0ff4cd53f\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = var.SUBNET != "" && can(regex("^subnet-[a-z0-9]{8,17}$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "PROXY_AMI" {
  description = "(Required) The AMI ID of the KNFSD image. No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$", var.PROXY_AMI))
    error_message = "PROXY_AMI must be a valid AMI ID."
  }
}

variable "PROXY_BASENAME" {
  description = "(Optional) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). Default: \"nfsproxy\"."
  type        = string
  nullable    = false
  default     = "nfsproxy"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,27}[a-zA-Z0-9]$", var.PROXY_BASENAME))
    error_message = "PROXY_BASENAME must be 2-29 characters long, contain only alphanumeric characters or hyphens, and cannot begin or end with a hyphen."
  }
}

variable "KEY_NAME" {
  description = "(Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "INSTANCE_TYPE" {
  description = "(Optional) The AWS EC2 instance type to use for the KNFSD cache. Default: \"i3en.6xlarge\"."
  type        = string
  default     = "i3en.6xlarge"
  validation {
    condition     = can(regex("^[a-z][0-9]?[a-z]*\\.(metal-[0-9]+xl|[a-z0-9]+)$", var.INSTANCE_TYPE))
    error_message = "INSTANCE_TYPE must be a valid AWS EC2 instance type."
  }
}

variable "KNFSD_NODES" {
  description = "(Optional) The number of KNFSD instances to deploy as part of the cluster. Default: \"1\"."
  type        = number
  nullable    = false
  default     = 1
}

variable "FSID_MODE" {
  description = "(Optional) How to assign FSIDs (File System Identifiers) to each export. The options are \"static\", \"local\", or \"external\". Default: \"external\"."
  type        = string
  nullable    = false
  default     = "external"
  validation {
    condition     = contains(["static", "local", "external"], var.FSID_MODE)
    error_message = "Valid values for FSID_MODE are 'static', 'local', or 'external'."
  }
}
