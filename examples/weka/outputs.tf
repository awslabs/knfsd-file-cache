# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "projects_dns_name" {
  description = "DNS name of the KNFSD projects node for NFS clients to mount."
  value       = module.projects.dns_name
}

output "software_dns_name" {
  description = "DNS name of the KNFSD software node for NFS clients to mount."
  value       = module.software.dns_name
}
