/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

locals {
  network_ip = google_compute_instance.source.network_interface[0].network_ip
}

output "network_ip" {
  description = "The IP address of the NFS source server."
  value       = local.network_ip
}

output "nfs_share" {
  description = "The combined NFS source server and mount point address."
  value       = "${local.network_ip}:/files"
}
