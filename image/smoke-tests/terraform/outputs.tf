/*
  Copyright 2022 Google LLC
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
 */

output "source_host" {
  description = "Name of the source NFS server."
  value       = local.source_host
}

output "proxy_host" {
  description = "DNS name of the KNFSD proxy."
  value       = local.proxy_host
}

output "proxy_asg" {
  description = "Name of the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.autoscaling_group_name
}

output "client_instance" {
  description = "DNS name of the KNFSD client instance."
  value       = google_compute_instance.client.name
}
