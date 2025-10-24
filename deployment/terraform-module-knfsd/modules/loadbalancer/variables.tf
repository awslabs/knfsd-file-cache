/*
 * Copyright 2020 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

variable "VERSION" {
  description = "(Required) The version of the KNFSD File Cache."
  type        = string
  nullable    = false
  default     = "1.1.0-alpha.11"
  validation {
    condition     = can(regex("^(?P<major>0|[1-9]\\d*)\\.(?P<minor>0|[1-9]\\d*)\\.(?P<patch>0|[1-9]\\d*)(?:-(?P<prerelease>(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$", var.VERSION))
    error_message = "VERSION must be a valid semantic version 2.0.0 format. Example: \"1.1.0-alpha.11\"."
  }
}

variable "SUBNET" {
  description = "(Required) The subnet ID to use for deployment of the Network Load Balancer. Example: \"subnet-038e337f0ff4cd53f\". No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-[a-z0-9]{8,17}$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "PROXY_BASENAME" {
  description = "(Required) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). No default."
  type        = string
  nullable    = false
  validation {
    condition     = var.PROXY_BASENAME != ""
    error_message = "PROXY_BASENAME is required."
  }
}

variable "DNS_NAME" {
  description = "(Optional) The fully qualified DNS name (FQDN) to use for the KNFSD proxy cluster. Defaults to: \"lb-knfsd.{PROXY_BASENAME}.aws.internal.\" [Note: the trailing period is required]. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.DNS_NAME == "" || can(regex("^(([a-z0-9][a-z0-9\\-]*[a-z0-9])|[a-z0-9]+\\.)*([a-z]+|xn\\-\\-[a-z0-9]+)\\.$$", var.DNS_NAME))
    error_message = "When provided, DNS_NAME must be a valid fully qualified domain name (FQDN) ending with a period. It should consist of valid domain name characters: alphanumeric, hyphen, and period(s)."
  }
}

variable "NFS_PORTS" {
  description = "(Required) The list of NFS ports (TCP & UDP) to use with the Network Load Balancer. Default: see \"map(object({port = number, check_port = number, name = string}))\"."
  # mountd default: tcp/udp:20048 as per IANA, RFC8267
  # 'showmount' udp:111 rpcbind/portmapper
  # tcp/udp:20049 (NFS over RDMA) skipped, tcp:20052 & tcp:20054 are outgoing ports, so not required. Outbound=0.0.0.0/0
  type = map(object({
    port       = number
    check_port = number
    name       = string
  }))
  nullable = false
  default = {
    "rpcbind-portmapper" = {
      port       = 111
      check_port = 111
      name       = "rpc-portmap"
    },
    "nfsd" = {
      port       = 2049
      check_port = 2049
      name       = "nfsd"
    },
    "mountd" = {
      port       = 20048
      check_port = 2049
      name       = "mountd"
    },
    "lockd-nlm" = {
      port       = 20050
      check_port = 2049
      name       = "lockd-nlm"
    },
    "statd" = {
      port       = 20051
      check_port = 2049
      name       = "statd"
    },
    "lockd" = {
      port       = 20053
      check_port = 2049
      name       = "lockd"
    },
    "nfs-callback" = {
      port       = 20055
      check_port = 2049
      name       = "nfs-callback"
    }
  }
}

variable "LOADBALANCER_IP" {
  description = "(Optional) The static private IPv4 address to use for the Network Load Balancer. If not specified, a random IP address will be assigned from the subnet. Default: \"null\"."
  type        = string
  nullable    = true
  default     = null
  validation {
    condition     = var.LOADBALANCER_IP == null || can(regex("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", var.LOADBALANCER_IP))
    error_message = "When provided, LOADBALANCER_IP must be a valid IPv4 address in dotted decimal notation."
  }
}

variable "HEALTHCHECK_INTERVAL_SECONDS" {
  description = "How frequently (in seconds) to probe if a proxy instance is healthy. This is measured from the start of one probe, to the start of the next probe. Default: \"60\"."
  type        = number
  nullable    = false
  default     = 60
  validation {
    condition     = var.HEALTHCHECK_INTERVAL_SECONDS >= 5 && var.HEALTHCHECK_INTERVAL_SECONDS <= 300
    error_message = "HEALTHCHECK_INTERVAL_SECONDS must be between 5 and 300 seconds."
  }
}

variable "HEALTHCHECK_TIMEOUT_SECONDS" {
  description = "How long (in seconds) to wait for a response from a probe. Must be less than or equal to \"HEALTHCHECK_INTERVAL_SECONDS\". Default: \"5\"."
  type        = number
  nullable    = false
  default     = 5
  validation {
    condition     = var.HEALTHCHECK_TIMEOUT_SECONDS >= 2 && var.HEALTHCHECK_TIMEOUT_SECONDS <= 120
    error_message = "HEALTHCHECK_TIMEOUT_SECONDS must be between 2 and 120 seconds."
  }
}

variable "HEALTHCHECK_HEALTHY_THRESHOLD" {
  description = "Number of sequential successful probe results for a proxy instance to be considered healthy. Default: \"3\"."
  type        = number
  nullable    = false
  default     = 3
  validation {
    condition     = var.HEALTHCHECK_HEALTHY_THRESHOLD >= 2 && var.HEALTHCHECK_HEALTHY_THRESHOLD <= 10
    error_message = "HEALTHCHECK_HEALTHY_THRESHOLD must be between 2 and 10."
  }
}

variable "HEALTHCHECK_UNHEALTHY_THRESHOLD" {
  description = "Number of sequential failed probe results for a proxy instance to be considered unhealthy. Default: \"3\"."
  type        = number
  nullable    = false
  default     = 3
  validation {
    condition     = var.HEALTHCHECK_UNHEALTHY_THRESHOLD >= 2 && var.HEALTHCHECK_UNHEALTHY_THRESHOLD <= 10
    error_message = "HEALTHCHECK_UNHEALTHY_THRESHOLD must be between 2 and 10."
  }
}
