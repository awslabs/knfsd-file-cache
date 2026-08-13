# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/vpc-endpoints/1.1.0-beta.2"
    ]
  }
}

provider "aws" {
  region = var.REGION
}

# get the current AWS partition (aws, aws-us-gov, aws-cn)
data "aws_partition" "current" {}

# get each selected subnet
data "aws_subnet" "selected" {
  for_each = toset(var.SUBNETS)
  id       = each.value
}

# get the VPC via the first selected subnet
data "aws_vpc" "selected" {
  id = data.aws_subnet.selected[var.SUBNETS[0]].vpc_id

  lifecycle {
    postcondition {
      condition     = length(distinct([for s in data.aws_subnet.selected : s.vpc_id])) == 1
      error_message = "All entries in SUBNETS must belong to the same VPC."
    }
  }
}

# local variables
locals {
  partition      = data.aws_partition.current.partition
  tags           = { "knfsd-file-cache:version" = var.VERSION }
  vpc_id         = data.aws_vpc.selected.id
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
  services = [
    "autoscaling",
    "ec2",
    "ec2messages",
    "events",
    "kms",
    "logs",
    "monitoring",
    "secretsmanager",
    "ssm",
    "ssmmessages",
    "sts"
  ]
  # The global IAM and Route 53 control-plane APIs are reachable via interface
  # VPC endpoints in all three partitions, but the endpoint shape differs:
  #   - AWS Commercial (aws): cross-region endpoints hosted in us-east-1
  #     (service_name "com.amazonaws.<service>" + service_region = us-east-1).
  #   - GovCloud (aws-us-gov) / China (aws-cn): ordinary same-region endpoints
  #     (service_name "com.amazonaws.<service>", no service_region).
  global_services = [
    "iam",
    "route53"
  ]
  cross_region_services       = local.partition == "aws" ? local.global_services : []
  same_region_global_services = local.partition == "aws" ? [] : local.global_services
  cross_region                = "us-east-1"
}

# resolve the partition-correct interface endpoint service name for each service
# com.amazonaws.<region>.<service> in aws/aws-us-gov
# cn.com.amazonaws.<region>.<service> in aws-cn
data "aws_vpc_endpoint_service" "regional" {
  for_each = toset(local.services)
  service  = each.value
}

# create security group for VPC endpoints (skipped when EXISTING_SECURITY_GROUP_ID is set)
resource "aws_security_group" "vpc_endpoints_sg" {
  count       = var.EXISTING_SECURITY_GROUP_ID == "" ? 1 : 0
  name        = "knfsd-vpc-endpoints-sg"
  description = "Security group for KNFSD VPC endpoints"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow all outbound"
  }

  tags = merge(local.tags, { Name = "knfsd-vpc-endpoints-sg" })
}

locals {
  # use the pre-existing security group when provided, otherwise the one
  # created by this module
  vpc_endpoints_sg_id = var.EXISTING_SECURITY_GROUP_ID != "" ? var.EXISTING_SECURITY_GROUP_ID : aws_security_group.vpc_endpoints_sg[0].id
}

resource "aws_vpc_endpoint" "knfsd_endpoints" {
  for_each = toset(local.services)

  vpc_id              = local.vpc_id
  service_name        = data.aws_vpc_endpoint_service.regional[each.value].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.SUBNETS
  private_dns_enabled = true
  security_group_ids  = [local.vpc_endpoints_sg_id]

  tags = merge(local.tags, { Name = "knfsd-vpc-endpoint-${each.value}" })
}

# Cross-region endpoints for the global IAM and Route 53 control-plane APIs.
# AWS Commercial partition only (hosted in us-east-1 via service_region).
resource "aws_vpc_endpoint" "knfsd_cross_region_endpoints" {
  for_each = toset(local.cross_region_services)

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${each.value}"
  service_region      = local.cross_region
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.SUBNETS
  private_dns_enabled = true
  security_group_ids  = [local.vpc_endpoints_sg_id]

  tags = merge(local.tags, { Name = "knfsd-vpc-endpoint-${each.value}-${local.cross_region}" })
}

# Same-region endpoints for the global IAM and Route 53 control-plane APIs.
# GovCloud (aws-us-gov) and China (aws-cn) partitions, which expose these as
# ordinary same-region interface endpoints (service_name "com.amazonaws.<service>",
# no service_region).
resource "aws_vpc_endpoint" "knfsd_global_endpoints" {
  for_each = toset(local.same_region_global_services)

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.SUBNETS
  private_dns_enabled = true
  security_group_ids  = [local.vpc_endpoints_sg_id]

  tags = merge(local.tags, { Name = "knfsd-vpc-endpoint-${each.value}" })
}

# DynamoDB Gateway endpoint requires route table id(s). The endpoint must be
# attached to the route tables that actually govern the selected subnets,
# otherwise instances in those subnets will not receive the DynamoDB prefix-list
# route and will fail to reach the service. The gateway endpoint itself is not
# subnet-scoped; it is associated with the union of route tables covering all
# of the selected subnets.

# route table(s) explicitly associated with each selected subnet (may be empty
# for a subnet that implicitly uses the VPC main route table)
data "aws_route_tables" "explicit" {
  for_each = toset(var.SUBNETS)
  vpc_id   = local.vpc_id
  filter {
    name   = "association.subnet-id"
    values = [each.value]
  }
}

# VPC main route table (always exists; used when a subnet has no explicit
# association and therefore implicitly uses the main route table)
data "aws_route_table" "main" {
  vpc_id = local.vpc_id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

locals {
  # the route table that actually governs traffic for each selected subnet:
  # the explicitly-associated route table if one exists, otherwise the VPC
  # main route table. Deduplicated so subnets sharing a route table (or falling
  # back to the main route table) only associate the gateway endpoint once.
  route_table_ids = distinct([
    for subnet in var.SUBNETS :
    length(data.aws_route_tables.explicit[subnet].ids) > 0 ? tolist(data.aws_route_tables.explicit[subnet].ids)[0] : data.aws_route_table.main.id
  ])
}

# resolve the partition-correct gateway endpoint service name
# com.amazonaws.<region>.dynamodb in aws/aws-us-gov
# cn.com.amazonaws.<region>.dynamodb in aws-cn
data "aws_vpc_endpoint_service" "dynamodb" {
  service      = "dynamodb"
  service_type = "Gateway"
}

resource "aws_vpc_endpoint" "knfsd_dynamodb" {
  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.dynamodb.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.route_table_ids

  tags = merge(local.tags, { Name = "knfsd-vpc-endpoint-dynamodb" })
}

# this solution collects anonymous operational metrics to help AWS improve the quality of features of the solution
resource "aws_cloudformation_stack" "metrics_vpc_endpoints" {
  name          = "knfsd-metrics-vpc-endpoints"
  on_failure    = "DO_NOTHING"
  tags          = local.tags
  template_body = <<STACK
    {
        "AWSTemplateFormatVersion": "2010-09-09",
        "Description": "(SO9129) - KNFSD-File-Cache. Version v${var.VERSION}",
        "Resources": {
            "EmptyResource": {
                "Type": "AWS::CloudFormation::WaitConditionHandle"
            }
        }
    }
    STACK
}
