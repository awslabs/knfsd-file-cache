# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "dns_name" {
  description = "The DNS address of the Network Load Balancer that the NFS clients will connect to."
  value       = module.knfsd_cluster.dns_name
}

output "loadbalancer_ipaddress" {
  description = "The IP address of the Network Load Balancer that the NFS clients will connect to."
  value       = module.knfsd_cluster.loadbalancer_ipaddress
}
