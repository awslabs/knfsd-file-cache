/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

data "google_project" "this" {
  project_id = var.PROJECT
}

locals {
  build_service_account = "${data.google_project.this.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "build" {
  for_each = toset([
    # Build image (and test terraform)
    "roles/compute.admin",

    # Deploy and test terraform
    "roles/dns.admin",
    "roles/file.editor",
    "roles/cloudsql.admin",
  ])

  project = var.PROJECT
  role    = each.key
  member  = "serviceAccount:${local.build_service_account}"

  depends_on = [google_project_service.services]
}

resource "google_project_iam_member" "build_assign_permissions" {
  project = var.PROJECT
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${local.build_service_account}"

  condition {
    title       = "KNFSD roles only"
    description = "Allow granting roles required to deploy KNFSD"
    expression  = <<-EOT
      api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([
        'roles/logging.logWriter',
        'roles/monitoring.metricWriter',
        'roles/cloudsql.client',
        'roles/cloudsql.instanceUser',
      ])
    EOT
  }

  depends_on = [google_project_service.services]
}

resource "google_service_account_iam_member" "build_use_proxy" {
  service_account_id = google_service_account.proxy.id
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.build_service_account}"
}

resource "google_service_account" "proxy" {
  project     = var.PROJECT
  account_id  = "knfsd-proxy"
  description = "KNFSD proxy cluster service account"
}

resource "google_project_iam_member" "proxy" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.PROJECT
  role    = each.key
  member  = "serviceAccount:${google_service_account.proxy.email}"
}
