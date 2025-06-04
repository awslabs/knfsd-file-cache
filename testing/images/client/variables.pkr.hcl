// Copyright 2023 Google LLC
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

variable "PROJECT" {
  description = "GCP Project where the image will be built and stored."
  type        = string
  default     = ""
}

variable "ZONE" {
  description = "The zone in which to launch the instance used to create the image. Example: \"us-west1-a\"."
  type        = string
  default     = ""
}

variable "INSTANCE_TYPE" {
  description = "The instance type used to build the image. This can be increased to improve build speeds. Defaults to \"n1-standard-2\"."
  type        = string
  default     = "n1-standard-2"
}

variable "BUILD_NAME" {
  description = "The name applied to all resources during the image build phase. Defaults to \"packer-knfsd-client-{{uuid}}\"."
  type        = string
  default     = "packer-knfsd-client-{{uuid}}"
}

variable "NETWORK_PROJECT" {
  description = "Project hosting the network when using shared VPC. Defaults to \"\"."
  type        = string
  default     = ""
}

variable "SUBNETWORK" {
  description = "The subnetwork the compute instance will use. Defaults to \"\"."
  type        = string
  default     = ""
}

variable "OMIT_EXTERNAL_IP" {
  description = "Use a private (internal) IP only. Defaults to \"true\"."
  type        = bool
  default     = true
}

variable "IMAGE_NAME" {
  description = "The unique name of the resulting image. Defaults to \"knfsd-client-{timestamp}\"."
  type        = string
  default     = ""
}

variable "USE_IAP" {
  description = "Whether to use an IAP proxy. Defaults to \"true\"."
  type        = bool
  default     = true
}

variable "USE_INTERNAL_IP" {
  description = "If true, use the instance's internal IP instead of its external IP during building. Defaults to \"true\"."
  type        = bool
  default     = true
}

variable "SKIP_CREATE_IMAGE" {
  description = "Skip creating the image. Useful for setting to \"true\" during a build test stage. Defaults to \"false\"."
  type        = bool
  default     = false
}
