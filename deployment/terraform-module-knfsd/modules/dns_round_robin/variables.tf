/*
 * Copyright 2020 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

variable "SUBNET" {
  description = "(Required) The single subnet ID to use for deployment of the KNFSD solution. Example: \"subnet-038e337f0ff4cd53f\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = var.SUBNET != "" && can(regex("^subnet-[a-z0-9]{8,17}$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "PROXY_BASENAME" {
  description = "(Required) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). No default."
  type        = string
  nullable    = false
  validation {
    condition     = var.PROXY_BASENAME == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,27}[a-zA-Z0-9]$", var.PROXY_BASENAME))
    error_message = "PROXY_BASENAME must be 2-29 characters long, contain only alphanumeric characters or hyphens, and cannot begin or end with a hyphen."
  }
}

variable "DNS_NAME" {
  description = "(Optional) The fully qualified domain name (FQDN) to assign the KNFSD proxy cluster. Defaults to: \"{PROXY_BASENAME}.knfsd.internal.\" [Note: the trailing period is required]. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.DNS_NAME == "" || can(regex("^(([a-z0-9][a-z0-9\\-]*[a-z0-9])|[a-z0-9]+\\.)*([a-z]+|xn\\-\\-[a-z0-9]+)\\.$$", var.DNS_NAME))
    error_message = "When provided, DNS_NAME must be a valid fully qualified domain name (FQDN) ending with a period. It should consist of valid domain name characters: alphanumeric, hyphen, and period(s)."
  }
}
