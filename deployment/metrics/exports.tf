/*
  Copyright 2022 Google LLC
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
 */

resource "google_monitoring_metric_descriptor" "exports_total_operations" {
  project      = var.PROJECT
  description  = "Total NFS operations received from NFS clients"
  display_name = "NFS Export Total Operations"
  type         = "knfsd/exports/total_operations"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "{operations}"
}

resource "google_monitoring_metric_descriptor" "exports_total_read_bytes" {
  project      = var.PROJECT
  description  = "Total bytes read by the NFS clients"
  display_name = "NFS Export Total Read Bytes"
  type         = "knfsd/exports/total_read_bytes"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "By"
}

resource "google_monitoring_metric_descriptor" "exports_total_write_bytes" {
  project      = var.PROJECT
  description  = "Total bytes wrote by the NFS clients"
  display_name = "NFS Export Total Write Bytes"
  type         = "knfsd/exports/total_write_bytes"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "By"
}
