/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.15.0"
    }
  }
}

resource "google_compute_disk" "source" {
  project = var.PROJECT
  zone    = var.ZONE
  name    = "${var.NAME}-nfs"
  image   = var.NFS_IMAGE
  size    = var.CAPACITY_GB == 0 ? null : var.CAPACITY_GB
  type    = "pd-ssd"
}

resource "google_compute_instance" "source" {
  project = var.PROJECT
  zone    = var.ZONE
  name    = var.NAME
  labels  = var.LABELS
  tags    = ["nfs-server"]

  machine_type     = "n1-standard-16"
  min_cpu_platform = "Intel Skylake"

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.IMAGE
      size  = 200
    }
  }

  attached_disk {
    source      = google_compute_disk.source.self_link
    device_name = "nfs"
  }

  network_interface {
    network    = var.NETWORK
    subnetwork = var.SUBNET
  }

  metadata_startup_script = file("${path.module}/scripts/startup")
  metadata = {
    "delay" = var.LATENCY_MS == 0 ? "" : "${var.LATENCY_MS}ms"
    "rate"  = var.RATE_LIMIT_MBIT == 0 ? "" : "${var.RATE_LIMIT_MBIT}MBit"
  }
}
