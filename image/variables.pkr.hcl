// Copyright 2023 Google LLC
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

variable "REGION" {
  description = "(Required) The name of the AWS region, such as \"us-east-1\", in which to launch the EC2 instance to create the AMI. No default."
  type        = string
  default     = ""
}

variable "SUBNET" {
  description = "(Required) The subnet the EC2 instance will use. No default."
  type        = string
  default     = ""
}

variable "ASSOCIATE_PUBLIC_IP_ADDRESS" {
  description = "(Optional) If using a non-default VPC, whether to forcefully associate a public IP address with the EC2 instance. Default: \"null\"."
  type        = bool
  default     = null
}

variable "SECURITY_GROUP_ID" {
  description = "(Optional) The ID of an existing, single security group to use instead of creating a temporary one. When specified, overrides \"TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP\" and \"TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS\". Default: \"\"."
  type        = string
  default     = ""
}

variable "SECURITY_GROUP_IDS" {
  description = "(Optional) A list of security group IDs to use instead of creating a temporary one. When specified, overrides \"TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP\" and \"TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS\". Default: \"[]\"."
  type        = list(string)
  default     = []
}

variable "TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS" {
  description = "(Optional) A list of CIDR blocks to allow access from when creating a temporary security group. When specified, overrides \"TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP\". Example: [\"10.0.0.0/8\", \"172.16.0.0/12\"]. Default: \"[]\"."
  type        = list(string)
  default     = []
}

variable "TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP" {
  description = "(Optional) Whether to allow access from the public IP address of the machine running Packer when creating a temporary security group. Only used when \"SECURITY_GROUP_ID\", \"SECURITY_GROUP_IDS\", and \"TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS\" are not specified. Default: \"true\"."
  type        = bool
  default     = true
}

variable "ARCH" {
  description = "(Optional) List of architectures to build. Valid values: [\"amd64\"], [\"arm64\"], or [\"amd64\", \"arm64\"]. Default: [\"amd64\", \"arm64\"]."
  type        = list(string)
  default     = ["amd64", "arm64"]
  validation {
    condition = alltrue([
      for arch in var.ARCH : contains(["amd64", "arm64"], arch)
    ]) && length(var.ARCH) > 0
    error_message = "ARCH must contain only 'amd64' and/or 'arm64'."
  }
}

variable "BUILD_NAME" {
  description = "(Optional) The name applied to all resources during the image build phase. Default: \"packer-knfsd-proxy-{version}-{timestamp}\"."
  type        = string
  default     = ""
}

variable "IMAGE_NAME" {
  description = "(Optional) The unique name of the resulting image. Default: \"knfsd-proxy-{version}\"."
  type        = string
  default     = ""
}

variable "SKIP_CREATE_IMAGE" {
  description = "(Optional) Skip creating the image. Useful for setting to \"true\" during a build test stage. Default: \"false\"."
  type        = bool
  default     = false
}

variable "IAM_INSTANCE_PROFILE" {
  description = "(Optional) The name of an IAM instance profile to attach to the build instance. Required if your custom scripts need to access AWS resources. Default: \"\"."
  type        = string
  default     = ""
}

variable "CUSTOM_PRE_BUILD_SCRIPT" {
  description = "(Optional) Path to a bash script file to run BEFORE the \"10_build.sh\" script. For example \"/home/$USER/myscript.sh\". Default: \"\"."
  type        = string
  default     = ""
}

variable "CUSTOM_POST_BUILD_SCRIPT" {
  description = "(Optional) Path to a bash script file to run AFTER the \"20_post_build.sh\" script. For example \"/home/$USER/myscript.sh\". Default: \"\"."
  type        = string
  default     = ""
}
