/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "autoscaling_group_name" {
  description = "Name of the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.autoscaling_group_name
}

output "autoscaling_group_security_group_id" {
  description = "Security Group ID for the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.autoscaling_group_security_group_id
}

output "dns_name" {
  description = "The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group."
  value       = module.proxy.dns_name
}

output "nfsproxy_loadbalancer_dnsaddress" {
  description = "The private DNS name of the Network Load Balancer."
  value       = module.proxy.nfsproxy_loadbalancer_dnsaddress
}

output "nfsproxy_loadbalancer_ipaddress" {
  description = "The private IP address of the Network Load Balancer."
  value       = module.proxy.nfsproxy_loadbalancer_ipaddress
}

output "nfsproxy_security_group_id" {
  description = "Security Group ID for the NFS clients to connect to the KNFSD proxy instances."
  value       = module.proxy.nfsproxy_security_group_id
}
