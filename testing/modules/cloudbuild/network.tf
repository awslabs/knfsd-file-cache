/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

locals {
  # format the service ranges in standard CIDR (IP/prefix) format.
  service_ranges = {
    for k, sa in google_compute_global_address.service_addresses :
    k => "${sa.address}/${sa.prefix_length}"
  }
}

resource "google_project_service" "servicenetworking" {
  project            = var.PROJECT
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "build" {
  project                 = var.PROJECT
  name                    = var.NETWORK
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "build" {
  project = google_compute_network.build.project
  network = google_compute_network.build.id
  region  = var.REGION
  name    = var.NETWORK

  ip_cidr_range            = "10.0.0.0/20"
  private_ip_google_access = true
}

resource "google_compute_global_address" "service_addresses" {
  for_each = toset(["worker-pool", "database"])
  project  = var.PROJECT
  name     = "${var.NETWORK}-${each.key}"

  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.build.name
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network = google_compute_network.build.id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    for _, a in google_compute_global_address.service_addresses : a.name
  ]
  depends_on = [
    google_project_service.servicenetworking,
  ]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.NETWORK}-cloudbuild-ssh"
  project = google_compute_network.build.project
  network = google_compute_network.build.id
  source_ranges = [
    # Allow Cloud Build Workers SSH access so they can run scripts on the VMs they're building.
    local.service_ranges["worker-pool"],

    # Allow SSH via the IAP tunnel to diagnose issues with VMs when running tests.
    "35.235.240.0/20"
  ]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Firewall rule to allow healthchecks from the GCP Healthcheck ranges
resource "google_compute_firewall" "allow_tcp_healthcheck" {
  name     = "${var.NETWORK}-allow-nfs-tcp-healthcheck"
  project  = google_compute_network.build.project
  network  = google_compute_network.build.id
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["2049"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]
  target_tags   = ["knfsd-cache-server"]
}

# Firewall rule to allow client to knfsd proxy (and knfsd proxy to source)
resource "google_compute_firewall" "allow_nfs" {
  name     = "${var.NETWORK}-allow-nfs"
  project  = google_compute_network.build.project
  network  = google_compute_network.build.id
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["111", "2049", "20048", "20050", "20051", "20052", "20053"]
  }

  source_tags = ["nfs-client", "knfsd-cache-server"]
  target_tags = ["knfsd-cache-server", "nfs-server"]
}

# Allow clients to access the knfsd-agent running on the proxy to perform tests.
resource "google_compute_firewall" "allow_http" {
  name     = "${var.NETWORK}-allow-http"
  project  = google_compute_network.build.project
  network  = google_compute_network.build.id
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_tags = ["nfs-client"]
  target_tags = ["knfsd-cache-server"]
}
