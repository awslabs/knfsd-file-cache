/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "load_balancer_ip_address" {
  description = "The IP address of the Network Load Balancer that the NFS clients will connect to."
  value       = module.nfs_proxy_cluster.nfsproxy_loadbalancer_ipaddress
}

output "load_balancer_dns_address" {
  description = "The DNS address of the Network Load Balancer that the NFS clients will connect to."
  value       = module.nfs_proxy_cluster.nfsproxy_loadbalancer_dnsaddress
}
