// Copyright 2023 Google LLC
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

variable "REGION" {
  description = "(Required) The name of the AWS region, such as \"us-east-1\", in which to launch the EC2 instance to create the AMI. No default."
  type        = string
  default     = ""
  validation {
    condition     = var.REGION == "" || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.REGION))
    error_message = "REGION must be empty or a valid AWS region format. Example: \"us-east-1\"."
  }
}

variable "SUBNET" {
  description = "(Optional) The subnet the EC2 instance will use. This is required if using a non-default VPC. Default: \"\"."
  type        = string
  default     = ""
  validation {
    condition     = var.SUBNET == "" || can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", var.SUBNET))
    error_message = "SUBNET must be empty or a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "DISTRIBUTION_REGIONS" {
  description = "(Optional) A list of AWS regions to distribute the AMI to. Default: \"[]\"."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for r in var.DISTRIBUTION_REGIONS : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    error_message = "DISTRIBUTION_REGIONS must all be valid AWS region formats. Example: \"us-east-1\"."
  }
}

variable "AMI_ENCRYPTED" {
  description = "(Optional) Whether the resulting AMI is encrypted. When \"true\" (default), the AMI is encrypted using the key referenced by \"KMS_KEY_ID\" (or the region's default \"aws/ebs\" key if \"KMS_KEY_ID\" is empty). When \"false\", the AMI is unencrypted. The AWS account-level \"EBS encryption by default\" setting (when enabled) overrides this to \"true\". Default: \"true\"."
  type        = bool
  default     = true
}

variable "KMS_KEY_ID" {
  description = "(Optional) Customer-managed KMS key identifier (key ID, alias, key ARN, or alias ARN) used to encrypt the AMI in the AWS build region. Empty uses the region's default \"aws/ebs\" key when \"AMI_ENCRYPTED = true\". Default: \"\"."
  type        = string
  default     = ""
  validation {
    condition = (
      var.KMS_KEY_ID == ""
      || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.KMS_KEY_ID))
      || can(regex("^mrk-[0-9a-f]{32}$", var.KMS_KEY_ID))
      || can(regex("^alias/[a-zA-Z0-9/_-]+$", var.KMS_KEY_ID))
      || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/", var.KMS_KEY_ID))
    )
    error_message = "KMS_KEY_ID must be empty or a valid KMS key ID, alias, key ARN, or alias ARN."
  }
}

variable "REGION_KMS_KEY_IDS" {
  description = "(Optional) Map of AWS region to customer-managed KMS key identifier used when distributing the AMI to that region via \"DISTRIBUTION_REGIONS\". Use when each destination region has a distinct CMK. Empty string in the map means use that AWS region's default \"aws/ebs\" key. When this map is empty, \"KMS_KEY_ID\" is reused for every region in \"DISTRIBUTION_REGIONS\" (suitable for multi-region KMS keys or AWS-managed \"aws/ebs\" defaults). Default: \"{}\"."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.REGION_KMS_KEY_IDS :
      can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", k))
      && (
        v == ""
        || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", v))
        || can(regex("^mrk-[0-9a-f]{32}$", v))
        || can(regex("^alias/[a-zA-Z0-9/_-]+$", v))
        || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/", v))
      )
    ])
    error_message = "REGION_KMS_KEY_IDS keys must be valid AWS region names and values must be empty or a valid KMS key ID, alias, key ARN, or alias ARN."
  }
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
  validation {
    condition     = var.SECURITY_GROUP_ID == "" || can(regex("^sg-[0-9a-f]{8}([0-9a-f]{9})?$", var.SECURITY_GROUP_ID))
    error_message = "SECURITY_GROUP_ID must be empty or a valid AWS security group ID format. Example: \"sg-038e337f0ff4cd53f\"."
  }
}

variable "SECURITY_GROUP_IDS" {
  description = "(Optional) A list of security group IDs to use instead of creating a temporary one. When specified, overrides \"TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP\" and \"TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS\". Default: \"[]\"."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for s in var.SECURITY_GROUP_IDS : can(regex("^sg-[0-9a-f]{8}([0-9a-f]{9})?$", s))])
    error_message = "SECURITY_GROUP_IDS must all be valid AWS security group ID formats. Example: \"sg-038e337f0ff4cd53f\"."
  }
}

variable "TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS" {
  description = "(Optional) A list of CIDR blocks to allow access from when creating a temporary security group. When specified, overrides \"TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP\". Example: [\"10.0.0.0/8\", \"172.16.0.0/12\"]. Default: \"[]\"."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for c in var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS : can(cidrnetmask(c))])
    error_message = "TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS must all be valid IPv4 CIDR blocks. Example: \"10.0.0.0/8\"."
  }
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
