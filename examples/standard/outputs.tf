/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "region" {
  description = "AWS region where the resources were created."
  value       = var.REGION
}

output "subnet" {
  description = "AWS subnet where the resources were created."
  value       = var.SUBNET
}

output "autoscaling_group_name" {
  description = "Name of the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.autoscaling_group_name
}

output "proxy_host" {
  description = "DNS name of the KNFSD proxy."
  value       = module.proxy.dns_name
}
