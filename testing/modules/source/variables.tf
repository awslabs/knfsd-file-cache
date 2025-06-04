/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

variable "PROJECT" {
  description = "(Required) GCP Project ID to configure for building NFS source server."
  type        = string
  default     = ""
}

variable "ZONE" {
  description = "(Required) GCP Zone that will be used to run NFS source server."
  type        = string
  default     = ""
}

variable "NETWORK" {
  description = "GCP network to use for NFS source server."
  type        = string
  default     = ""
}

variable "SUBNET" {
  description = "GCP subnetwork to use for NFS source server."
  type        = string
  default     = ""
}

variable "NAME" {
  description = "Instance name of the NFS source server."
  type        = string
  default     = ""
}

variable "LABELS" {
  description = "GCP Labels to apply to the NFS source server."
  type        = map(string)
  default     = {}
}

variable "IMAGE" {
  # Avoid using proxy image for the source server to avoid possible issues
  # with the latest NFS versions. This way the source server uses older
  # stable versions and the only component being tested with newer versions
  # is the proxy.
  description = "Image for NFS source server (boot disk)."
  type        = string
  default     = ""
}

variable "NFS_IMAGE" {
  description = "Disk image for NFS share."
  type        = string
  default     = ""
}

variable "CAPACITY_GB" {
  description = "Size of the source NFS share in GB."
  type        = number
  default     = 1024
}

variable "LATENCY_MS" {
  description = "Latency (delay) to apply in milliseconds, 0 means no additional latency."
  type        = number
  default     = 0
}

variable "RATE_LIMIT_MBIT" {
  description = "Rate limit to apply in megabits per second, 0 means unlimited."
  type        = number
  default     = 0
}
