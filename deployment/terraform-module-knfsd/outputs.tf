/*
 * Copyright 2020 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "autoscaling_group_name" {
  description = "Name of the KNFSD proxy Auto Scaling Group."
  value       = aws_autoscaling_group.knfsd_asg.name
}

output "dns_name" {
  description = "The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group."
  value = (
    var.TRAFFIC_MODE == "loadbalancer" ? one(module.loadbalancer[*].dns_name) :
    var.TRAFFIC_MODE == "dns_round_robin" ? one(module.dns_round_robin[*].dns_name) :
    null
  )
}

output "nfsproxy_loadbalancer_dnsaddress" {
  description = "The private DNS name of the Network Load Balancer."
  value       = one(module.loadbalancer[*].dns_name)
}

output "nfsproxy_loadbalancer_ipaddress" {
  description = "The private IP address of the Network Load Balancer."
  value       = one(module.loadbalancer[*].ip_address)
}

output "nfsproxy_security_group_id" {
  description = "Security Group ID for the KNFSD Network Load Balancer or Auto Scaling Group."
  value = (
    var.TRAFFIC_MODE == "loadbalancer" ? one(module.loadbalancer[*].lb_security_group_id) :
    var.TRAFFIC_MODE == "dns_round_robin" ? aws_security_group.nfsproxy_asg_sg.id :
    null
  )
}
