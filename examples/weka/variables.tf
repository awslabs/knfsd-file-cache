# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "REGION" {
  description = "(Required) The AWS region to use for deployment of the KNFSD File Cache. Example: \"us-east-1\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.REGION))
    error_message = "REGION must be a valid AWS region format. Example: \"us-east-1\"."
  }
}

variable "SUBNET" {
  description = "(Required) The single subnet ID to use for deployment of the KNFSD File Cache. Example: \"subnet-038e337f0ff4cd53f\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", var.SUBNET))
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

variable "WEKA_NFS_GATEWAY" {
  description = "(Required) The IP address of the Weka NFS gateway. No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(cidrhost("${var.WEKA_NFS_GATEWAY}/32", 0))
    error_message = "WEKA_NFS_GATEWAY must be a valid IPv4 address. Example: \"10.0.0.10\"."
  }
}

variable "EXPORT_MAP_SOFTWARE" {
  description = "(Required) A list of NFS SOFTWARE exports to mount from the source and re-export in the format \"<SOURCE_IP>;<SOURCE_EXPORT>;<TARGET_EXPORT>\". No default."
  type        = string
  nullable    = false
}
