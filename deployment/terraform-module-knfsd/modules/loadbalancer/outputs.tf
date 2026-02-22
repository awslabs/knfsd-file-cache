/*
 * Copyright 2020 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "dns_name" {
  description = "The private DNS name that was created for the KNFSD Network Load Balancer."
  value       = var.DNS_NAME == "" ? aws_route53_record.nfsproxy_lb_cname[0].fqdn : aws_route53_record.nfsproxy_lb_cname_custom[0].fqdn
}

output "ip_address" {
  description = "The private IP address of the KNFSD Network Load Balancer."
  value       = one(data.dns_a_record_set.nfsproxy_lb_ip.addrs)
}

output "lb_security_group_id" {
  description = "The ID of the KNFSD Network Load Balancer Security Group."
  value       = aws_security_group.nfsproxy_lb_sg.id
}

output "lb_target_groups" {
  description = "Map of NFS port names to target group ARNs."
  value       = { for k, v in aws_lb_target_group.nfsproxy_lb_tg : k => v.arn }
}
