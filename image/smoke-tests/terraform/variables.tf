/*
  Copyright 2022 Google LLC
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
 */

variable "PROJECT" {
  description = "GCP project ID."
  type        = string
  default     = ""
}

variable "SUBNET" {
  description = "(Required) The single subnet ID to use for deployment of the KNFSD solution."
  type        = string
  nullable    = false
  validation {
    condition     = var.SUBNET != ""
    error_message = "SUBNET is required."
  }
}

variable "ZONE" {
  description = "GCP zone to run benchmarks."
  type        = string
  default     = ""
}

variable "NETWORK" {
  description = "GCP network to use for smoke tests."
  type        = string
  default     = ""
}

variable "SUBNETWORK" {
  description = "GCP subnetwork to use for smoke tests."
  type        = string
  default     = ""
}

variable "PROXY_IMAGE" {
  description = "Compute image for the NFS proxy."
  type        = string
  default     = ""
}

variable "CLIENT_IMAGE" {
  description = "Compute image for test NFS client."
  type        = string
  default     = "family/test-nfs-client"
}

variable "PREFIX" {
  description = "Prefix used for deployment. Used as the name or prefix for resources such as network, router, etc."
  type        = string
  default     = "smoke-tests"
}
