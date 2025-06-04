/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
}

module "proxy" {
  source         = "../../deployment/terraform-module-knfsd"
  REGION         = var.REGION
  SUBNET         = var.SUBNET
  KNFSD_NODES    = 1
  PROXY_AMI      = var.PROXY_AMI
  PROXY_BASENAME = var.PROXY_BASENAME
  TRAFFIC_MODE   = "dns_round_robin"
  KEY_NAME       = var.KEY_NAME
  FSID_MODE      = "static" # this should not be used in production or with more than a single node
  EXPORT_MAP     = var.EXPORT_MAP
  INSTANCE_TAGS  = { "knfsd-file-cache:examples" = "basic" }
}
