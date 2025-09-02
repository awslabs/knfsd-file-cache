/*
  Copyright 2022 Google LLC
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0.1"
    }
  }
}

provider "google" {
  project = var.PROJECT
  zone    = var.ZONE
}

locals {
  source_host = google_filestore_instance.source.networks[0].ip_addresses[0]
  proxy_host  = module.proxy.dns_name
}

resource "google_filestore_instance" "source" {
  project  = var.PROJECT
  name     = "${var.PREFIX}-source"
  tier     = "BASIC_HDD"
  location = var.ZONE

  networks {
    network = var.NETWORK
    modes   = ["MODE_IPV4"]
  }

  file_shares {
    name        = "files"
    capacity_gb = 1024
  }
}

module "proxy" {
  source = "../../../deployment/terraform-module-knfsd"

  SUBNET = var.SUBNET

  TRAFFIC_MODE = "dns_round_robin"

  PROXY_BASENAME = "${var.PREFIX}-proxy"
  PROXY_AMI      = var.PROXY_IMAGE

  # The smoke tests rely on using a single node so that the test client reliably
  # connects to a specific instance. Also, the smoke tests only create a single
  # client so they'd only ever connect to one instance.
  KNFSD_NODES = 1

  EXPORT_MAP = "${local.source_host};/files;/files"
}

# nosemgrep: gcp-compute-boot-disk-encryption
resource "google_compute_instance" "client" {
  name         = "${var.PREFIX}-client"
  machine_type = "n1-standard-1"
  tags         = ["nfs-client"]

  boot_disk {
    initialize_params {
      image = var.CLIENT_IMAGE
    }
  }

  shielded_instance_config {
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  network_interface {
    network    = var.NETWORK
    subnetwork = var.SUBNETWORK
  }

  metadata = {
    "source_host" = local.source_host,
    "proxy_host"  = local.proxy_host,
  }
}
