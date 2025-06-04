/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
}

locals {
  source = module.source.network_ip
}

module "source" {
  source  = "../../modules/source"
  NAME    = "${var.NAME}-source"
  PROJECT = var.PROJECT
  ZONE    = var.ZONE
  NETWORK = var.NETWORK
  SUBNET  = var.SUBNETWORK

  LABELS = {
    deployment = var.NAME
    component  = "source"
  }

  IMAGE       = var.SOURCE_IMAGE
  NFS_IMAGE   = "source-files"
  CAPACITY_GB = 0
}
