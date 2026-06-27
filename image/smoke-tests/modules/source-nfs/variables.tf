# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "REGION" {
  description = "(Required) AWS region in which to launch the source NFS server."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.REGION))
    error_message = "REGION must be a valid AWS region format. Example: \"us-east-1\"."
  }
}

variable "NAME" {
  description = "(Required) Instance Name tag of the source NFS server."
  type        = string
  nullable    = false
}

variable "SUBNET" {
  description = "(Required) ID of the subnet the source NFS instance will be launched into. The subnet's VPC CIDR is used as the NFS export allowlist."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "SECURITY_GROUP_ID" {
  description = "(Required) Security group ID to attach to the source NFS instance."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^sg-[0-9a-f]{8}([0-9a-f]{9})?$", var.SECURITY_GROUP_ID))
    error_message = "SECURITY_GROUP_ID must be a valid AWS security group ID format. Example: \"sg-038e337f0ff4cd53f\"."
  }
}

variable "ASSOCIATE_PUBLIC_IP_ADDRESS" {
  description = "(Optional) Whether to associate a public IPv4 address with the source NFS instance. When \"null\", the instance inherits the subnet's \"MapPublicIpOnLaunch\" attribute. Set to \"true\" to force a public IP (e.g. an IGW-only public subnet without a NAT), or \"false\" to never assign one. Default: \"false\"."
  type        = bool
  nullable    = true
  default     = false
}

variable "INSTANCE_TYPE" {
  description = "(Optional) Instance type to launch. Default 'i3en.large' which has local NVMe instance storage. Use 'im4gn.large' for arm64."
  type        = string
  nullable    = false
  default     = "i3en.large"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.INSTANCE_TYPE))
    error_message = "INSTANCE_TYPE must be a valid AWS instance type. Example: \"i3en.large\"."
  }
}

variable "AMI_ID" {
  description = "(Optional) AMI ID for the source NFS server. If empty, the latest Ubuntu 24.04 amd64 AMI is resolved from SSM Parameter Store."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.AMI_ID == "" || can(regex("^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$", var.AMI_ID))
    error_message = "AMI_ID must be empty or a valid AMI ID format. Example: \"ami-0abcdef1234567890\"."
  }
}

variable "ARCH" {
  description = "(Optional) Architecture (\"amd64\" or \"arm64\") used to resolve the default Ubuntu AMI when AMI_ID is empty."
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.ARCH)
    error_message = "ARCH must be either \"amd64\" or \"arm64\"."
  }
}

variable "ROOT_VOLUME_SIZE_GB" {
  description = "(Optional) Root EBS volume size in GB. Default 20."
  type        = number
  nullable    = false
  default     = 20
  validation {
    condition     = var.ROOT_VOLUME_SIZE_GB >= 8
    error_message = "ROOT_VOLUME_SIZE_GB must be at least 8 GB."
  }
}

variable "LATENCY_MS" {
  description = "(Optional) Latency (delay) to apply via tc, in milliseconds. 0 means no additional latency."
  type        = number
  nullable    = false
  default     = 0
  validation {
    condition     = var.LATENCY_MS >= 0
    error_message = "LATENCY_MS must be greater than or equal to 0."
  }
}

variable "RATE_LIMIT_MBIT" {
  description = "(Optional) Rate limit to apply via tc, in megabits per second. 0 means unlimited."
  type        = number
  nullable    = false
  default     = 0
  validation {
    condition     = var.RATE_LIMIT_MBIT >= 0
    error_message = "RATE_LIMIT_MBIT must be greater than or equal to 0."
  }
}

variable "TAGS" {
  description = "(Optional) Additional tags applied to the source NFS instance."
  type        = map(string)
  default     = {}
}
