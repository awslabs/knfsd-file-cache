# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "REGION" {
  description = "(Required) AWS region in which to launch the NFS client."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.REGION))
    error_message = "REGION must be a valid AWS region format. Example: \"us-east-1\"."
  }
}

variable "SUBNET" {
  description = "(Required) ID of the subnet the NFS client instance will be launched into."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "SECURITY_GROUP_ID" {
  description = "(Required) Security group ID to attach to the NFS client instance."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^sg-[0-9a-f]{8}([0-9a-f]{9})?$", var.SECURITY_GROUP_ID))
    error_message = "SECURITY_GROUP_ID must be a valid AWS security group ID format. Example: \"sg-038e337f0ff4cd53f\"."
  }
}

variable "PREFIX" {
  description = "(Required) Resource name prefix used to disambiguate parallel test runs."
  type        = string
  nullable    = false
}

variable "ARCH" {
  description = "(Optional) Architecture (\"amd64\" or \"arm64\") used to resolve the Ubuntu 26.04 client AMI from SSM. Must match INSTANCE_TYPE family. Default: \"amd64\"."
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.ARCH)
    error_message = "ARCH must be \"amd64\" or \"arm64\"."
  }
}

variable "INSTANCE_TYPE" {
  description = "(Optional) EC2 instance type for the NFS client. Must match ARCH. Default: \"m6i.2xlarge\"."
  type        = string
  default     = "m6i.2xlarge"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.(metal(-[0-9]+xl)?|[a-z0-9]+)$", var.INSTANCE_TYPE))
    error_message = "INSTANCE_TYPE must be a valid AWS EC2 instance type."
  }
}

variable "ASSOCIATE_PUBLIC_IP_ADDRESS" {
  description = "(Optional) Whether to associate a public IPv4 address with the client instance. When \"null\", the instance inherits the subnet's \"MapPublicIpOnLaunch\" attribute. Default: \"null\"."
  type        = bool
  nullable    = true
  default     = null
}

variable "SOURCE_HOST" {
  description = "(Required) Private IP / hostname of the source NFS server, surfaced to the client via the \"knfsd-file-cache:source-host\" tag."
  type        = string
  nullable    = false
}

variable "PROXY_HOST" {
  description = "(Required) DNS name of the KNFSD proxy, surfaced to the client via the \"knfsd-file-cache:proxy-host\" tag."
  type        = string
  nullable    = false
}

variable "CLUSTER_READY" {
  description = "(Optional) Dependency handle (e.g. the proxy module's cluster_ready output) gating client creation until the proxy cluster is ready. Default: \"null\"."
  type        = any
  nullable    = true
  default     = null
}
