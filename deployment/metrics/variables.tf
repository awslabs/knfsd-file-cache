# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "VERSION" {
  description = "(Internal) The version of the KNFSD Monitoring Dashboard."
  type        = string
  nullable    = false
  default     = "14"
}
