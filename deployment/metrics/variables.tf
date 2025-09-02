/*
  Copyright 2022 Google LLC
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
 */

variable "PROJECT" {
  description = "(Required) The Google Cloud Project that the KNFSD Metrics are being deployed to. No default."
  type        = string
  nullable    = false
  validation {
    condition     = var.PROJECT != ""
    error_message = "PROJECT is required."
  }
}
