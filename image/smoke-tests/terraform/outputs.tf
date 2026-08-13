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

output "fsid_mode" {
  description = "FSID_MODE the KNFSD proxy was deployed with. The Go driver skips the FSID table checks unless this is \"external\"."
  value       = var.FSID_MODE
}

output "fsid_table_name" {
  description = "Name of the DynamoDB table storing the FSID mappings. Empty unless FSID_MODE is \"external\"."
  value       = try(module.proxy.database_config.table_name, "")
}

output "region" {
  description = "AWS region of the smoke-test deployment."
  value       = var.REGION
}
