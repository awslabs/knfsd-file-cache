/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# launch template security group
resource "aws_security_group" "nfsproxy_asg_sg" {
  name        = "${local.name}-asg-sg"
  description = "knfsd security group for knfsd instances in the ASG"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-asg-sg" })
}

# asg sg ingress rule: TCP
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_asg_ingress_tcp" {
  for_each          = var.NFS_PORTS
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow inbound TCP traffic for port: ${each.value.port} - ${each.value.name}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = local.vpc_cidr_block
  tags              = merge(local.tags, { Name = "tcp-${each.value.port}-${each.value.name}" })
}

# asg sg ingress rule: UDP
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_asg_ingress_udp" {
  for_each          = var.NFS_PORTS
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow inbound UDP traffic for port: ${each.value.port} - ${each.value.name}"
  ip_protocol       = "udp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = local.vpc_cidr_block
  tags              = merge(local.tags, { Name = "udp-${each.value.port}-${each.value.name}" })
}

# asg sg ingress rule: knfsd-agent
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_asg_ingress_knfsd_agent" {
  count             = var.ENABLE_KNFSD_AGENT ? 1 : 0
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow inbound HTTP/80 traffic for knfsd-agent"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = local.vpc_cidr_block
  tags              = merge(local.tags, { Name = "tcp-80-knfsd-agent" })
}

# asg sg egress rule
resource "aws_vpc_security_group_egress_rule" "nfsproxy_asg_egress" {
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = var.ASG_EGRESS_CIDR_BLOCK
  tags              = merge(local.tags, { Name = "egress-all" })
}
