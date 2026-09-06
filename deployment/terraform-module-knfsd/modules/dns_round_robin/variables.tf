# Copyright 2020 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "VERSION" {
  description = "(Required) The version of the KNFSD File Cache."
  type        = string
  nullable    = false
  default     = "1.1.0-beta.3"
  validation {
    condition     = can(regex("^(?P<major>0|[1-9]\\d*)\\.(?P<minor>0|[1-9]\\d*)\\.(?P<patch>0|[1-9]\\d*)(?:-(?P<prerelease>(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$", var.VERSION))
    error_message = "VERSION must be a valid semantic version 2.0.0 format. Example: \"1.1.0-beta.3\"."
  }
}

variable "SUBNET" {
  description = "(Required) The single subnet ID to use for deployment of the KNFSD solution. Example: \"subnet-038e337f0ff4cd53f\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "PROXY_BASENAME" {
  description = "(Required) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,27}[a-zA-Z0-9]$", var.PROXY_BASENAME))
    error_message = "PROXY_BASENAME must be 2-29 characters long, contain only alphanumeric characters or hyphens, and cannot begin or end with a hyphen."
  }
}

variable "DNS_NAME" {
  description = "(Optional) The fully qualified domain name (FQDN) to assign the KNFSD proxy cluster. Defaults to: \"{PROXY_BASENAME}.aws.internal.\" [Note: the trailing period is required]. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.DNS_NAME == "" || can(regex("^(([a-z0-9][a-z0-9\\-]*[a-z0-9])|[a-z0-9]+\\.)*([a-z]+|xn\\-\\-[a-z0-9]+)\\.$", var.DNS_NAME))
    error_message = "When provided, DNS_NAME must be a valid fully qualified domain name (FQDN) ending with a period. It should consist of valid domain name characters: alphanumeric, hyphen, and period(s)."
  }
}

variable "EXISTING_LAMBDA_ROLE_ARN" {
  description = "(Optional) ARN of a pre-existing IAM role to use for the static_ip Lambda function instead of creating one. When set, the module skips creating the Lambda IAM role and its policy. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.EXISTING_LAMBDA_ROLE_ARN == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9+=,.@_/-]+$", var.EXISTING_LAMBDA_ROLE_ARN))
    error_message = "When provided, EXISTING_LAMBDA_ROLE_ARN must be a valid IAM role ARN format. Example: \"arn:*:iam::123456789012:role/StaticIpLambdaRole\"."
  }
}
