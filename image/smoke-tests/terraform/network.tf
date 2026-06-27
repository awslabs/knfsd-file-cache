# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Self-created security groups for the source-NFS server and the NFS client.
# Both are scoped to the VPC CIDR of the selected subnet, so the smoke tests
# run standalone against an existing or default VPC without any pre-wired
# security groups.
#
# NFS ports opened for TCP and UDP. The outgoing-only ports (statd 20052,
# sm-notify 20054) and NFS-over-RDMA (20049) are intentionally NOT opened.
#   111   rpcbind/portmapper   2049  nfsd            20048 mountd
#   20050 lockd (nlm)          20051 statd           20053 lockd
#   20055 nfs-callback
locals {
  nfs_ports = [111, 2049, 20048, 20050, 20051, 20053, 20055]
}

# Source NFS server (EC2 with local NVMe). Ingress from the VPC CIDR, which
# encompasses all private ENIs including the KNFSD proxy ASG.
resource "aws_security_group" "source_nfs" {
  name        = "${var.PREFIX}-source-nfs-sg"
  description = "Source NFS EC2 server (smoke)"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name                         = "${var.PREFIX}-source-nfs-sg"
    "knfsd-file-cache:run"       = var.PREFIX
    "knfsd-file-cache:component" = "source-nfs"
  }
}

resource "aws_security_group_rule" "source_nfs_tcp_from_vpc" {
  for_each          = toset([for p in local.nfs_ports : tostring(p)])
  type              = "ingress"
  description       = "NFS TCP/${each.value} from KNFSD proxy ASG (VPC CIDR)"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = aws_security_group.source_nfs.id
}

resource "aws_security_group_rule" "source_nfs_udp_from_vpc" {
  for_each          = toset([for p in local.nfs_ports : tostring(p)])
  type              = "ingress"
  description       = "NFS UDP/${each.value} from KNFSD proxy ASG (VPC CIDR)"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "udp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = aws_security_group.source_nfs.id
}

resource "aws_security_group_rule" "source_nfs_egress" {
  #checkov:skip=CKV_AWS_382
  type              = "egress"
  description       = "Outbound for package install"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.source_nfs.id
}

# NFS client (EC2 instance running the smoke-test remote binary). Reached
# keylessly over SSM, so no ingress is required.
resource "aws_security_group" "client" {
  name        = "${var.PREFIX}-nfs-client-sg"
  description = "NFS client EC2 instance (smoke)"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name                         = "${var.PREFIX}-nfs-client-sg"
    "knfsd-file-cache:run"       = var.PREFIX
    "knfsd-file-cache:component" = "nfs-client"
  }
}

resource "aws_security_group_rule" "client_egress_nfs_tcp_to_vpc" {
  for_each          = toset([for p in local.nfs_ports : tostring(p)])
  type              = "egress"
  description       = "NFS TCP/${each.value} to KNFSD proxy ASG (VPC CIDR)"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = aws_security_group.client.id
}

resource "aws_security_group_rule" "client_egress_nfs_udp_to_vpc" {
  for_each          = toset([for p in local.nfs_ports : tostring(p)])
  type              = "egress"
  description       = "NFS UDP/${each.value} to KNFSD proxy ASG (VPC CIDR)"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "udp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = aws_security_group.client.id
}

resource "aws_security_group_rule" "client_egress_dns_udp" {
  type              = "egress"
  description       = "DNS resolution"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.client.id
}

resource "aws_security_group_rule" "client_egress_https" {
  type              = "egress"
  description       = "HTTPS for package install and SSM endpoints"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.client.id
}

resource "aws_security_group_rule" "client_egress_http" {
  type              = "egress"
  description       = "HTTP for package install and knfsd-agent on proxy"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.client.id
}
