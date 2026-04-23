/*
 * Copyright 2020 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.42.0"
    }
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.5.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/modules/loadbalancer/1.1.0-alpha.24"
    ]
  }
}

# get the selected subnet
data "aws_subnet" "selected" {
  id = var.SUBNET
}

# get the VPC via selected subnet
data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

# get the IP address of the load balancer
data "dns_a_record_set" "nfsproxy_lb_ip" {
  host = aws_lb.nfsproxy_lb.dns_name
}

# lookup existing hosted zone when DNS_NAME is provided
data "aws_route53_zone" "existing" {
  count        = var.DNS_NAME != "" ? 1 : 0
  name         = join(".", slice(split(".", var.DNS_NAME), 1, length(split(".", var.DNS_NAME))))
  private_zone = true
  vpc_id       = local.vpc_id
}

# local variables
locals {
  tags     = { "knfsd-file-cache:version" = var.VERSION }
  vpc_id   = data.aws_vpc.selected.id
  dns_name = trimspace(coalesce(var.DNS_NAME, "${var.PROXY_BASENAME}.aws.internal."))
  port_cidr_rules = {
    for item in flatten([
      for port_key, port_value in var.NFS_PORTS : [
        for idx, cidr in var.VPC_CIDR : {
          key  = "${port_key}-cidr${idx}"
          port = port_value.port
          name = port_value.name
          cidr = cidr
        }
      ]
    ]) : item.key => item
  }
}

# network load balancer; name=32 chars max (29 chars) + "-lb" (3 suffix)
# nosemgrep: missing-alb-drop-http-headers, missing-aws-cross-zone-lb, missing-aws-lb-deletion-protection
resource "aws_lb" "nfsproxy_lb" {
  name               = "${substr(var.PROXY_BASENAME, 0, 29)}-lb"
  load_balancer_type = "network"
  internal           = true
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.nfsproxy_lb_sg.id]
  subnet_mapping {
    subnet_id            = var.SUBNET
    private_ipv4_address = var.LOADBALANCER_IP
  }
  tags = local.tags
}

# lb security group
# https://wiki.debian.org/SecuringNFS
resource "aws_security_group" "nfsproxy_lb_sg" {
  name        = "${var.PROXY_BASENAME}-lb-sg"
  description = "knfsd security group for Network Load Balancer"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${var.PROXY_BASENAME}-lb-sg" })
}

# lb sg ingress rule: TCP
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_lb_ingress_tcp" {
  for_each          = local.port_cidr_rules
  security_group_id = aws_security_group.nfsproxy_lb_sg.id
  description       = "Allow inbound TCP traffic for port: ${each.value.port} - ${each.value.name}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  tags              = merge(local.tags, { Name = "tcp-${each.value.port}-${each.value.name}" })
}

# lb sg ingress rule: UDP
resource "aws_vpc_security_group_ingress_rule" "nfsproxy_lb_ingress_udp" {
  for_each          = local.port_cidr_rules
  security_group_id = aws_security_group.nfsproxy_lb_sg.id
  description       = "Allow inbound UDP traffic for port: ${each.value.port} - ${each.value.name}"
  ip_protocol       = "udp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  tags              = merge(local.tags, { Name = "udp-${each.value.port}-${each.value.name}" })
}

# lb sg egress rule
resource "aws_vpc_security_group_egress_rule" "nfsproxy_lb_egress" {
  for_each          = { for idx, cidr in var.VPC_CIDR : tostring(idx) => cidr }
  security_group_id = aws_security_group.nfsproxy_lb_sg.id
  description       = "Allow all outbound traffic to KNFSD proxy security group"
  ip_protocol       = "-1" # all protocols
  cidr_ipv4         = each.value
  tags              = merge(local.tags, { Name = "egress-all-vpc" })
}

# dynamically create load balancer listeners
# https://manpages.ubuntu.com/manpages/jammy/man5/nfs.conf.5.html
# https://manpages.ubuntu.com/manpages/jammy/man8/statd.8.html
resource "aws_lb_listener" "nfsproxy_lb_listener" {
  for_each = var.NFS_PORTS

  load_balancer_arn = aws_lb.nfsproxy_lb.arn
  port              = each.value.port
  protocol          = "TCP_UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nfsproxy_lb_tg[each.key].arn
  }

  tags = merge(local.tags, { Name = "${var.PROXY_BASENAME}-lb-listener-${each.value.port}-${each.value.name}" })
}

# dynamically create load balancer target groups
# name=32 chars max, (20 chars) + "-lb-tg-00000" (12 suffix)
resource "aws_lb_target_group" "nfsproxy_lb_tg" {
  for_each = var.NFS_PORTS

  name        = "${substr(var.PROXY_BASENAME, 0, 20)}-lb-tg-${each.value.port}"
  port        = each.value.port
  protocol    = "TCP_UDP"
  target_type = "instance"
  vpc_id      = local.vpc_id

  health_check {
    interval            = var.HEALTHCHECK_INTERVAL_SECONDS
    port                = each.value.check_port
    protocol            = "TCP"
    timeout             = var.HEALTHCHECK_TIMEOUT_SECONDS
    healthy_threshold   = var.HEALTHCHECK_HEALTHY_THRESHOLD
    unhealthy_threshold = var.HEALTHCHECK_UNHEALTHY_THRESHOLD
  }

  tags = merge(local.tags, { Name = "${var.PROXY_BASENAME}-lb-tg-${each.value.port}-${each.value.name}" })
}

# create a private route53 DNS zone for the load balancer
resource "aws_route53_zone" "lb" {
  count         = var.DNS_NAME == "" ? 1 : 0
  name          = local.dns_name
  comment       = "Internal DNS for KNFSD Network Load Balancer"
  force_destroy = true
  vpc {
    vpc_id = local.vpc_id
  }
  tags = merge(local.tags, { Name = trimsuffix(local.dns_name, ".") })
}

# create a route53 CNAME record for the load balancer
resource "aws_route53_record" "nfsproxy_lb_cname" {
  count   = var.DNS_NAME == "" ? 1 : 0
  name    = "lb-knfsd"
  type    = "CNAME"
  ttl     = 120
  records = [aws_lb.nfsproxy_lb.dns_name]
  zone_id = aws_route53_zone.lb[0].zone_id
}

# create a custom route53 CNAME record for the load balancer in pre-existing zone
resource "aws_route53_record" "nfsproxy_lb_cname_custom" {
  count   = var.DNS_NAME != "" ? 1 : 0
  zone_id = data.aws_route53_zone.existing[0].zone_id
  name    = split(".", var.DNS_NAME)[0]
  type    = "CNAME"
  ttl     = 120
  records = [aws_lb.nfsproxy_lb.dns_name]
}
