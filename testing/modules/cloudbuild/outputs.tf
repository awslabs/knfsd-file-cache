/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "network" {
  description = "Full ID of the network for use with the \"_NETWORK\" substitution."
  value       = google_compute_network.build.id
}

output "subnetwork" {
  description = "Full ID of the subnetwork for use with the \"_SUBNETWORK\" substitution."
  value       = google_compute_subnetwork.build.id
}

output "worker_pool" {
  description = "Full ID of the worker pool for use with the \"_WORKER_POOL\" substitution."
  value       = google_cloudbuild_worker_pool.pool.id
}

output "docker_repository_url" {
  description = "URL for the build Docker repository for use with the \"_DOCKER_REPOSITORY\" substitution."
  value       = "${google_artifact_registry_repository.docker_repository.location}-docker.pkg.dev/${google_artifact_registry_repository.docker_repository.project}/${google_artifact_registry_repository.docker_repository.repository_id}"
}

output "proxy_service_account" {
  description = "Email address of the KNFSD proxy service account for use with the \"_PROXY_SERVICE_ACCOUNT\" substitution."
  value       = google_service_account.proxy.email
}
