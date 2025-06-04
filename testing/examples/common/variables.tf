/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

variable "PROJECT" {
  description = "GCP project ID."
  type        = string
  default     = ""
}

variable "ZONE" {
  description = "GCP zone to run benchmarks."
  type        = string
  default     = ""
}

variable "SOURCE_IMAGE" {
  description = "Compute image for the source NFS server."
  type        = string
  default     = "family/nfs"
}

variable "NAME" {
  description = "Name of deployment. Used as the name or prefix for resources such as network, router, etc."
  type        = string
  default     = ""
}

variable "NETWORK" {
  description = "Network to use for source instance."
  type        = string
  default     = ""
}

variable "SUBNETWORK" {
  description = "Subnet to use for source instance."
  type        = string
  default     = ""
}
