/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

variable "PROJECT" {
  description = "(Required) GCP Project ID to configure for building images."
  type        = string
  default     = ""
}

variable "REGION" {
  description = "(Required) GCP Region that will be used to build images."
  type        = string
  default     = ""
}

variable "NETWORK" {
  description = "(Optional) Name of private VPC network to create for use by Cloud Build. Defaults to \"knfsd-build\"."
  type        = string
  default     = "knfsd-build"
}

variable "WORKER_POOL" {
  description = "(Optional) Name of Cloud Build private worker pool to create. Defaults to \"knfsd-build\"."
  type        = string
  default     = "knfsd-build"
}

variable "DOCKER_REPOSITORY" {
  description = "(Optional) Name of the Docker repository to create. This is used to store Docker images used by Cloud Build. Defaults to \"knfsd-docker\"."
  type        = string
  default     = "knfsd-docker"
}
