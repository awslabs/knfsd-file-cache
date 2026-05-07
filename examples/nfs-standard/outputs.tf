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

output "database_config" {
  description = "Database configuration for deployed RDS PostgreSQL database. Only available when database is deployed by this module."
  value       = length(module.proxy.database_config) > 0 ? module.proxy.database_config : null
}

output "database_iam_policy" {
  description = "The ARN of the IAM policy for rds-db:connect database access. Only available when database is deployed by this module."
  value       = module.proxy.database_iam_policy
}

output "dns_name" {
  description = "The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group."
  value       = module.proxy.dns_name
}

output "loadbalancer_ipaddress" {
  description = "The private IP address of the Network Load Balancer."
  value       = module.proxy.loadbalancer_ipaddress
}

output "knfsd_security_group_id" {
  description = "Security Group ID for the NFS clients to connect to the KNFSD proxy instances."
  value       = module.proxy.knfsd_security_group_id
}
