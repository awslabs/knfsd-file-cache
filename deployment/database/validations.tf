/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# Subnet metadata used for VPC/AZ validation of FSID_DB_SUBNET_IDS.
data "aws_subnet" "db_members" {
  for_each = var.FSID_DB_SUBNET_IDS != null ? toset(var.FSID_DB_SUBNET_IDS) : toset([])
  id       = each.value
}

# DB subnet group metadata used for VPC validation of FSID_DB_SUBNET_GROUP_NAME.
data "aws_db_subnet_group" "existing" {
  count = var.FSID_DB_SUBNET_GROUP_NAME != null ? 1 : 0
  name  = var.FSID_DB_SUBNET_GROUP_NAME
}

# To maintain Tf v1.2 support, we need to use null_resource to validate cross-referencing variables.
resource "null_resource" "validations" {
  lifecycle {
    precondition {
      condition     = !(var.FSID_DB_SUBNET_GROUP_NAME != null && var.FSID_DB_SUBNET_IDS != null)
      error_message = "FSID_DB_SUBNET_GROUP_NAME and FSID_DB_SUBNET_IDS are mutually exclusive; set only one (or leave both null to use the AWS default DB subnet group)."
    }

    # Most of these preconditions are conditional. Terraform 1.2 does not have
    # support for some kind of "enabled" or "when" condition, so write the
    # conditions in the form:
    #   condition = (when ? check : true)
    #
    # This roughly translates to
    #   if when then
    #     check precondition
    #   else
    #     skip precondition

    precondition {
      condition = (
        var.FSID_DB_SUBNET_IDS != null
        ? contains(var.FSID_DB_SUBNET_IDS, var.SUBNET)
        : true
      )
      error_message = "FSID_DB_SUBNET_IDS must include SUBNET (${var.SUBNET}); the DB instance's subnet must belong to its DB subnet group."
    }

    precondition {
      condition = (
        var.FSID_DB_SUBNET_GROUP_NAME != null
        ? data.aws_db_subnet_group.existing[0].vpc_id == local.vpc_id
        : true
      )
      error_message = "FSID_DB_SUBNET_GROUP_NAME must belong to the same VPC as var.SUBNET (${var.SUBNET}, VPC: ${local.vpc_id})."
    }

    precondition {
      condition = (
        var.FSID_DB_SUBNET_IDS != null
        ? alltrue([for s in data.aws_subnet.db_members : s.vpc_id == local.vpc_id])
        : true
      )
      error_message = "All subnets in FSID_DB_SUBNET_IDS must belong to the same VPC as var.SUBNET."
    }

    precondition {
      condition = (
        var.FSID_DB_SUBNET_IDS != null
        ? length(distinct([for s in data.aws_subnet.db_members : s.availability_zone])) >= 2
        : true
      )
      error_message = "FSID_DB_SUBNET_IDS must span at least 2 distinct availability zones (AWS RDS requirement)."
    }
  }
}
