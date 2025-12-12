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
      version = "~> 7.13.0"
    }
  }
}

resource "google_project_service" "services" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "servicenetworking.googleapis.com",
    "artifactregistry.googleapis.com",
  ])

  project = var.PROJECT
  service = each.key
}

resource "google_cloudbuild_worker_pool" "pool" {
  project  = var.PROJECT
  name     = var.WORKER_POOL
  location = var.REGION
  worker_config {
    disk_size_gb   = 100
    machine_type   = "e2-standard-2"
    no_external_ip = false
  }
  network_config {
    peered_network          = google_compute_network.build.id
    peered_network_ip_range = local.service_ranges["worker-pool"]
  }
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_artifact_registry_repository" "docker_repository" {
  project       = var.PROJECT
  location      = var.REGION
  format        = "DOCKER"
  repository_id = var.DOCKER_REPOSITORY
  description   = "Docker repository for knfsd images"
  depends_on    = [google_project_service.services]
}
