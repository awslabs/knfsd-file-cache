/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "fanout_dns_name" {
  description = "The DNS name of the fanout proxy"
  value       = module.nfs_proxy_fanout.dns_name
}

output "cluster_dns_name" {
  description = "The DNS name of the cluster proxy"
  value       = module.nfs_proxy_cluster.dns_name
}
