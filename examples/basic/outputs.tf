# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "autoscaling_group_name" {
  description = "Name of the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.autoscaling_group_name
}

output "autoscaling_group_security_group_id" {
  description = "Security Group ID for the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.autoscaling_group_security_group_id
}

output "dns_name" {
  description = "The private DNS name of the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.dns_name
}

output "knfsd_security_group_id" {
  description = "Security Group ID for the NFS clients to connect to the KNFSD proxy instances."
  value       = module.proxy.knfsd_security_group_id
}
