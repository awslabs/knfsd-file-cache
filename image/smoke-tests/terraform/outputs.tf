# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "source_host" {
  description = "Private IP of the source NFS server."
  value       = module.source_nfs.private_ip
}

output "proxy_host" {
  description = "DNS name of the KNFSD proxy."
  value       = module.proxy.dns_name
}

output "proxy_asg" {
  description = "Name of the KNFSD proxy Auto Scaling Group."
  value       = module.proxy.autoscaling_group_name
}

output "client_instance_id" {
  description = "Instance ID of the test NFS client."
  value       = module.nfs_client.instance_id
}

output "region" {
  description = "AWS region of the smoke-test deployment."
  value       = var.REGION
}
