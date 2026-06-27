# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "instance_id" {
  description = "ID of the source NFS EC2 instance."
  value       = aws_instance.source.id
}

output "private_ip" {
  description = "Private IP address of the source NFS EC2 instance."
  value       = aws_instance.source.private_ip
}

output "private_dns" {
  description = "Private DNS name of the source NFS EC2 instance."
  value       = aws_instance.source.private_dns
}

output "nfs_share" {
  description = "Combined NFS source server address and export path (NFSv3/v4 compatible)."
  value       = "${aws_instance.source.private_ip}:/files"
}

output "vpc_cidr" {
  description = "VPC CIDR used for the NFS export allowlist."
  value       = local.vpc_cidr
}
