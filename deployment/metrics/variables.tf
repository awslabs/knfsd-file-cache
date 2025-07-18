/*
  Copyright 2022 Google LLC
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
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

variable "PROJECT" {
  description = "(Required) The Google Cloud Project that the KNFSD Metrics are being deployed to. No default."
  type        = string
  nullable    = false
  validation {
    condition     = var.PROJECT != ""
    error_message = "PROJECT is required."
  }
}
