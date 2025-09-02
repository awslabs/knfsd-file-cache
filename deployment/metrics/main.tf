/*
  Copyright 2021 Google LLC
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

locals {
  mount_labels = {
    "server" : "Source NFS server of the mount",
    "instance" : "Proxy instance the client is connected to",
  }
  mount_operation_labels = merge(local.mount_labels, {
    "operation" : "NFS operation name",
  })
}

resource "google_monitoring_metric_descriptor" "dentry_cache_active_objects" {
  project      = var.PROJECT
  description  = "The number of active objects in the Linux Dentry Cache"
  display_name = "Dentry Cache Active Objects"
  type         = "knfsd/dentry_cache_active_objects"
  metric_kind  = "GAUGE"
  value_type   = "INT64"
  unit         = "1"
}

resource "google_monitoring_metric_descriptor" "dentry_cache_objsize" {
  project      = var.PROJECT
  description  = "The total size of the objects in the Linux Dentry Cache"
  display_name = "Dentry Cache Object Size"
  type         = "knfsd/dentry_cache_objsize"
  metric_kind  = "GAUGE"
  value_type   = "INT64"
  unit         = "By"
}

resource "google_monitoring_metric_descriptor" "nfs_inode_cache_active_objects" {
  project      = var.PROJECT
  description  = "The number of active objects in the Linux NFS inode Cache"
  display_name = "NFS inode Cache Cache Active Objects"
  type         = "knfsd/nfs_inode_cache_active_objects"
  metric_kind  = "GAUGE"
  value_type   = "INT64"
  unit         = "1"
}

resource "google_monitoring_metric_descriptor" "nfs_inode_cache_objsize" {
  project      = var.PROJECT
  description  = "The total size of the objects in the Linux NFS inode Cache"
  display_name = "NFS inode Cache Object Size"
  type         = "knfsd/nfs_inode_cache_objsize"
  metric_kind  = "GAUGE"
  value_type   = "INT64"
  unit         = "By"
}

resource "google_monitoring_metric_descriptor" "nfsiostat_mount_read_exe" {
  project      = var.PROJECT
  description  = "The average read operation EXE per NFS client mount over the past 60 seconds (KNFSD --> Source Filer)"
  display_name = "nfsiostat Mount Read EXE"
  type         = "knfsd/nfsiostat_mount_read_exe"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "ms"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "nfsiostat_mount_read_rtt" {
  project      = var.PROJECT
  description  = "The average read operation RTT per NFS client mount over the past 60 seconds (KNFSD --> Source Filer)"
  display_name = "nfsiostat Mount Read RTT"
  type         = "knfsd/nfsiostat_mount_read_rtt"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "ms"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "nfsiostat_mount_write_exe" {
  project      = var.PROJECT
  description  = "The average write operation EXE per NFS client mount over the past 60 seconds (KNFSD --> Source Filer)"
  display_name = "nfsiostat Mount Write EXE"
  type         = "knfsd/nfsiostat_mount_write_exe"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "ms"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "nfsiostat_mount_write_rtt" {
  project      = var.PROJECT
  description  = "The average write operation RTT per NFS client mount over the past 60 seconds (KNFSD --> Source Filer)"
  display_name = "nfsiostat Mount Write RTT"
  type         = "knfsd/nfsiostat_mount_write_rtt"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "ms"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "nfsiostat_ops_per_second" {
  project      = var.PROJECT
  description  = "The number of NFS operations per second per NFS client mount over the past 60 seconds (KNFSD --> Source Filer)"
  display_name = "nfsiostat Mount Operations Per Second"
  type         = "knfsd/nfsiostat_ops_per_second"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "1"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "nfsiostat_rpc_backlog" {
  project      = var.PROJECT
  description  = "The RPC Backlog per NFS client mount over the past 60 seconds (KNFSD --> Source Filer)"
  display_name = "nfsiostat Mount RPC Backlog"
  type         = "knfsd/nfsiostat_rpc_backlog"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "1"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "mount_read_bytes" {
  project      = var.PROJECT
  description  = "Bytes read from remote NFS server"
  display_name = "NFS Mount Read Bytes"
  type         = "knfsd/mount/read_bytes"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "By"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "mount_write_bytes" {
  project      = var.PROJECT
  description  = "Bytes wrote to remote NFS server"
  display_name = "NFS Mount Write Bytes"
  type         = "knfsd/mount/write_bytes"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "By"

  dynamic "labels" {
    for_each = local.mount_labels
    content {
      key         = labels.key
      value_type  = "STRING"
      description = labels.value
    }
  }
}

resource "google_monitoring_metric_descriptor" "nfs_connections" {
  project      = var.PROJECT
  description  = "The number of NFS Clients connected to the KNFSD filer (used for autoscaling)"
  display_name = "KNFSD NFS Clients Connected"
  type         = "knfsd/nfs_connections"
  metric_kind  = "GAUGE"
  value_type   = "INT64"
  unit         = "1"
}

resource "google_monitoring_metric_descriptor" "fscache_oldest_file" {
  project      = var.PROJECT
  description  = "Age of the oldest file in FS-Cache"
  display_name = "Age of the oldest file in FS-Cache"
  type         = "knfsd/fscache_oldest_file"
  metric_kind  = "GAUGE"
  value_type   = "INT64"
  unit         = "s"
}

resource "google_monitoring_dashboard" "knfsd_monitoring_dashboard" {
  project        = var.PROJECT
  dashboard_json = file("${path.module}/dashboard/dashboard.json")
}
