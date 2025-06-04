/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

locals {
  service_names = [
    "autoscaling",
    "ec2",
    "events",
    "kms",
    "logs",
    "monitoring",
    "secretsmanager",
    "ssm",
    "ssmmessages",
    "sts"
  ]
  endpoints = var.ENABLE_VPC_ENDPOINTS ? { for service in local.service_names : service => service } : {}
}

# launch template security group
resource "aws_security_group" "nfsproxy_asg_sg" {
  name        = "${local.name}-asg-sg"
  description = "knfsd security group for knfsd instances in the ASG"
  vpc_id      = local.vpc_id
  tags = {
    Name = "${local.name}-asg-sg"
  }
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
  tags = {
    Name = "tcp-${each.value.port}-${each.value.name}"
  }
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
  tags = {
    Name = "udp-${each.value.port}-${each.value.name}"
  }
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
  tags = {
    Name = "tcp-80-knfsd-agent"
  }
}

# asg sg egress rule
resource "aws_vpc_security_group_egress_rule" "nfsproxy_asg_egress" {
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = var.ASG_EGRESS_CIDR_BLOCK
  tags = {
    Name = "egress-all"
  }
}

# asg sg egress rule for vpc endpoints
resource "aws_vpc_security_group_egress_rule" "nfsproxy_asg_egress_vpc_endpoints" {
  count             = var.ENABLE_VPC_ENDPOINTS ? 1 : 0
  security_group_id = aws_security_group.nfsproxy_asg_sg.id
  description       = "Allow HTTPS/443 outbound traffic to VPC endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = local.vpc_cidr_block
  tags = {
    Name = "tcp-443-vpc-endpoints"
  }
}

# vpc endpoints security group
resource "aws_security_group" "vpc_endpoints_sg" {
  count       = var.ENABLE_VPC_ENDPOINTS ? 1 : 0
  name        = "${local.name}-vpc-endpoints-sg"
  description = "knfsd security group for VPC Endpoints"
  vpc_id      = local.vpc_id
  tags = {
    Name = "${local.name}-vpc-endpoints-sg"
  }
}

# vpc endpoints security group ingress rule
resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_ingress" {
  count             = var.ENABLE_VPC_ENDPOINTS ? 1 : 0
  security_group_id = aws_security_group.vpc_endpoints_sg[0].id
  description       = "Allow HTTPS/443 inbound traffic from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = local.vpc_cidr_block
  tags = {
    Name = "tcp-443-vpc-endpoints"
  }
}

# vpc endpoints security group egress rule
resource "aws_vpc_security_group_egress_rule" "vpc_endpoints_egress" {
  count             = var.ENABLE_VPC_ENDPOINTS ? 1 : 0
  security_group_id = aws_security_group.vpc_endpoints_sg[0].id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = local.vpc_cidr_block
  tags = {
    Name = "egress-vpc-endpoints"
  }
}

# vpc endpoints
resource "aws_vpc_endpoint" "vpc_endpoint" {
  for_each            = local.endpoints
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.REGION}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.SUBNET]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints_sg[0].id]
}
