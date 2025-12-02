/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# local variables for security group rules
locals {
  port_cidr_rules = {
    for item in flatten([
      for port_key, port_value in var.NFS_PORTS : [
        for idx, cidr in local.vpc_cidr : {
          key  = "${port_key}-cidr${idx}"
          port = port_value.port
          name = port_value.name
          cidr = cidr
        }
      ]
    ]) : item.key => item
  }
}

# launch template security group
resource "aws_security_group" "nfsproxy_asg_sg" {
  name        = "${local.name}-asg-sg"
  description = "knfsd security group for knfsd instances in the ASG"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-asg-sg" })
}

# asg sg ingress rule: TCP
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_asg_ingress_tcp" {
  for_each          = local.port_cidr_rules
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow inbound TCP traffic for port: ${each.value.port} - ${each.value.name}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  tags              = merge(local.tags, { Name = "tcp-${each.value.port}-${each.value.name}" })
}

# asg sg ingress rule: UDP
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_asg_ingress_udp" {
  for_each          = local.port_cidr_rules
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow inbound UDP traffic for port: ${each.value.port} - ${each.value.name}"
  ip_protocol       = "udp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  tags              = merge(local.tags, { Name = "udp-${each.value.port}-${each.value.name}" })
}

# asg sg ingress rule: knfsd-agent
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_asg_ingress_knfsd_agent" {
  for_each          = var.ENABLE_KNFSD_AGENT ? { for idx, cidr in local.vpc_cidr : tostring(idx) => cidr } : {}
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow inbound HTTP/80 traffic for knfsd-agent"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
  tags              = merge(local.tags, { Name = "tcp-80-knfsd-agent" })
}

# asg sg egress rule
resource "aws_vpc_security_group_egress_rule" "nfsproxy_asg_egress" {
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = var.ASG_EGRESS_CIDR
  tags              = merge(local.tags, { Name = "egress-all" })
}
