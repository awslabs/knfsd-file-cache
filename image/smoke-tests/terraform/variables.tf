# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "REGION" {
  description = "(Required) The AWS region for the smoke-test deployment. Example: \"us-east-1\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.REGION))
    error_message = "REGION must be a valid AWS region format. Example: \"us-east-1\"."
  }
}

variable "SUBNET" {
  description = "(Required) The ID of the private subnet to deploy into. Example: \"subnet-038e337f0ff4cd53f\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "PROXY_AMI" {
  description = "(Required) The AMI ID of the KNFSD proxy under test. No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$", var.PROXY_AMI))
    error_message = "PROXY_AMI must be a valid AMI ID."
  }
}

variable "ASSOCIATE_PUBLIC_IP_ADDRESS" {
  description = "(Optional) Whether to associate a public IPv4 address with the source-NFS, proxy, and client instances. When \"null\", each instance inherits the subnet's \"MapPublicIpOnLaunch\" attribute. Set to \"true\" to force a public IP (e.g. running standalone in an IGW-only public subnet with no NAT or VPC endpoints), or \"false\" to never assign one. Security groups still block all external ingress regardless. Default: \"null\"."
  type        = bool
  nullable    = true
  default     = null
}

variable "PREFIX" {
  description = "(Optional) Resource name prefix. Used to disambiguate parallel test runs. The Go driver overrides this with random.UniqueID() at runtime. Must begin with \"knfsd\" so that created IAM, CloudFormation, and EventBridge resources fall under the \"knfsd-*\" ARN scope."
  type        = string
  default     = "knfsd-smoke"
  validation {
    condition     = can(regex("^knfsd", var.PREFIX))
    error_message = "PREFIX must begin with \"knfsd\" to match the \"knfsd-*\" IAM resource scope."
  }
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
  description = "(Optional) EC2 instance type for the smoke-test client. Must match ARCH. Default: \"m6i.2xlarge\"."
  type        = string
  default     = "m6i.2xlarge"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.(metal(-[0-9]+xl)?|[a-z0-9]+)$", var.INSTANCE_TYPE))
    error_message = "INSTANCE_TYPE must be a valid AWS EC2 instance type."
  }
}

variable "FSID_MODE" {
  description = "(Optional) FSID_MODE passed to the proxy module. \"external\" deploys the DynamoDB FSID table and enables the FSID table checks; \"static\" and \"local\" skip them. Default: \"external\"."
  type        = string
  nullable    = false
  default     = "external"
  validation {
    condition     = contains(["static", "local", "external"], var.FSID_MODE)
    error_message = "Valid values for FSID_MODE are 'static', 'local', or 'external'."
  }
}
