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
  description = "(Required) The single subnet ID to use for deployment of the FSx for OpenZFS source filer and KNFSD File Caches. Example: \"subnet-038e337f0ff4cd53f\". No default."
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

variable "KEY_NAME" {
  description = "(Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "INSTANCE_TYPE" {
  description = "(Optional) The AWS EC2 instance type to use for the KNFSD cache. Default: \"i3en.12xlarge\"."
  type        = string
  default     = "i3en.12xlarge"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.(metal(-[0-9]+xl)?|[a-z0-9]+)$", var.INSTANCE_TYPE))
    error_message = "INSTANCE_TYPE must be a valid AWS EC2 instance type."
  }
}

variable "GLOBAL_TAGS" {
  description = "(Optional) AWS TAGS to apply to ALL AWS resources created by this example, including the KNFSD File Cache. Default: {}."
  type        = map(string)
  nullable    = false
  default     = {}
  validation {
    condition = length(var.GLOBAL_TAGS) <= 40 && alltrue([
      for k, v in var.GLOBAL_TAGS :
      can(regex("^[a-zA-Z0-9+=._:@-]{1,128}$", k)) && !contains([".", "..", "_index"], k) && !can(regex("^(?i)aws:", k)) && length(v) <= 256
    ])
    error_message = "GLOBAL_TAGS allows at most 40 tags. Keys must be 1-128 characters using only a-z, A-Z, 0-9, and + - = . _ : @ (IMDS compatible), must not start with \"aws:\", and values must be 256 characters or fewer."
  }
}
