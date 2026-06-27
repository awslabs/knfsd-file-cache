# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "instance_id" {
  description = "Instance ID of the NFS client EC2 instance."
  value       = aws_instance.client.id
}

output "private_ip" {
  description = "Private IP address of the NFS client EC2 instance."
  value       = aws_instance.client.private_ip
}
