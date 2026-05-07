/*
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

output "loadbalancer_ipaddress" {
  description = "The private IP address of the Network Load Balancer."
  value       = module.proxy.loadbalancer_ipaddress
}

output "knfsd_security_group_id" {
  description = "Security Group ID for the NFS clients to connect to the KNFSD proxy instances."
  value       = module.proxy.knfsd_security_group_id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket backing the S3 Files filesystem."
  value       = aws_s3_bucket.s3files.id
}

output "s3files_mount_target_dns_name" {
  description = "DNS name of the S3 Files mount target."
  value       = "${data.aws_subnet.selected.availability_zone_id}.${aws_s3files_mount_target.s3files.id}.s3files.${var.REGION}.on.aws"
}

output "s3files_mount_target_ipv4_address" {
  description = "IPv4 address of the S3 Files mount target."
  value       = aws_s3files_mount_target.s3files.ipv4_address
}
