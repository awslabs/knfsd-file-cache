# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "VERSION" {
  description = "(Internal) The version of the KNFSD Monitoring Dashboard."
  type        = string
  nullable    = false
  default     = "17"
}

variable "GLOBAL_TAGS" {
  description = "(Optional) AWS TAGS to apply to ALL AWS resources created by this module. Default: {}."
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
