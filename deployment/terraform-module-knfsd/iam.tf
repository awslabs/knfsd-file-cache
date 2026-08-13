# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# get the current AWS account id
data "aws_caller_identity" "current" {}

# get the current AWS partition (aws, aws-us-gov, aws-cn)
data "aws_partition" "current" {}

# local variables
locals {
  account_id     = data.aws_caller_identity.current.account_id
  partition      = data.aws_partition.current.partition
  netapp_enabled = var.ENABLE_NETAPP_AUTO_DETECT && var.NETAPP_SECRET != ""
  netapp_region  = var.NETAPP_SECRET_REGION != "" ? var.NETAPP_SECRET_REGION : local.region
}

# IAM instance profile for KNFSD proxy instances (skipped when EXISTING_INSTANCE_PROFILE_NAME is set)
resource "aws_iam_instance_profile" "knfsd_instance_profile" {
  count = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  name  = "${local.name}-instance-profile"
  role  = aws_iam_role.knfsd_instance_role[0].name
  tags  = local.tags
}

locals {
  knfsd_instance_profile_name = var.EXISTING_INSTANCE_PROFILE_NAME != "" ? var.EXISTING_INSTANCE_PROFILE_NAME : aws_iam_instance_profile.knfsd_instance_profile[0].name
}

# IAM role for KNFSD proxy instances (skipped when EXISTING_INSTANCE_PROFILE_NAME is set)
resource "aws_iam_role" "knfsd_instance_role" {
  count       = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  name        = "${local.name}-instance-role"
  description = "IAM role for KNFSD proxy instances"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
  force_detach_policies = true
  tags                  = local.tags
}

# IAM policy document for EC2 instance "status" tagging & OTEL resource detection
data "aws_iam_policy_document" "ec2_instance_tags_policy_document" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags", "ec2:DescribeTags"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:*"]
  }
}

# IAM policy for EC2 instance "status" tagging & OTEL resource detection
resource "aws_iam_policy" "ec2_instance_tags_policy" {
  count  = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  name   = "${local.name}-ec2-instance-tags-policy"
  policy = data.aws_iam_policy_document.ec2_instance_tags_policy_document.json
  tags   = local.tags
}

# IAM role policy attachment for EC2 instance "status" tagging & OTEL resource detection
resource "aws_iam_role_policy_attachment" "ec2_instance_tags_policy_attachment" {
  count      = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = aws_iam_policy.ec2_instance_tags_policy[0].arn
}

# IAM policy document for autoscaling access for metrics via CW Agent to CloudWatch
data "aws_iam_policy_document" "autoscaling_policy_document" {
  statement {
    effect    = "Allow"
    actions   = ["autoscaling:DescribeAutoScalingInstances"]
    resources = ["*"]
  }
}

# IAM policy for autoscaling access for metrics via CW Agent to CloudWatch
resource "aws_iam_policy" "autoscaling_policy" {
  count  = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  name   = "${local.name}-autoscaling-policy"
  policy = data.aws_iam_policy_document.autoscaling_policy_document.json
  tags   = local.tags
}

# IAM role policy attachment for autoscaling access for metrics via CW Agent to CloudWatch
resource "aws_iam_role_policy_attachment" "autoscaling_policy_attachment" {
  count      = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = aws_iam_policy.autoscaling_policy[0].arn
}

# IAM policy document for SSM Parameter Store access
data "aws_iam_policy_document" "ssm_parameter_store_policy_document" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParametersByPath"]
    resources = [
      "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/knfsd/${local.name}",
      "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/knfsd/${local.name}/*"
    ]
  }
}

# IAM policy for SSM Parameter Store access
resource "aws_iam_policy" "ssm_parameter_store_policy" {
  count  = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  name   = "${local.name}-ssm-parameter-store-policy"
  policy = data.aws_iam_policy_document.ssm_parameter_store_policy_document.json
  tags   = local.tags
}

# IAM role policy attachment for SSM Parameter Store access
resource "aws_iam_role_policy_attachment" "ssm_parameter_store_policy_attachment" {
  count      = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = aws_iam_policy.ssm_parameter_store_policy[0].arn
}

# IAM role policy attachment for CloudWatch
resource "aws_iam_role_policy_attachment" "knfsd_instance_role_cloudwatch_policy" {
  count      = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM role policy attachment for Amazon SSM
resource "aws_iam_role_policy_attachment" "knfsd_instance_role_ssm_policy" {
  count      = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# new DATABASE deployment
# add IAM DynamoDB table access policy only if database == external & deployed
resource "aws_iam_role_policy_attachment" "knfsd_instance_role_db_policy" {
  count      = local.deploy_fsid_database && var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = module.fsid_database[0].db_iam_policy
}

# external/reuse DATABASE deployment
# add custom IAM DynamoDB table access policy if database == external & not deployed
# for both user-provided custom policy ARN and fanout deployments with module output
resource "aws_iam_role_policy_attachment" "knfsd_instance_role_external_db_policy" {
  count      = local.custom_fsid_database && var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = var.FSID_DATABASE_IAM_POLICY
}

# IAM policy document for netapp-exports secret access
data "aws_iam_policy_document" "netapp_exports_policy_document" {
  count = local.netapp_enabled ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:${local.partition}:secretsmanager:${local.netapp_region}:${local.account_id}:secret:${var.NETAPP_SECRET}-??????"]
  }
}

# IAM policy for netapp-exports secret access
resource "aws_iam_policy" "knfsd_instance_role_netapp_exports_policy" {
  count  = local.netapp_enabled && var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  name   = "${local.name}-netapp-exports-policy"
  policy = data.aws_iam_policy_document.netapp_exports_policy_document[0].json
  tags   = local.tags
}

# IAM role policy attachment for netapp-exports secret access
# if var.ENABLE_NETAPP_AUTO_DETECT == true & var.NETAPP_SECRET != ""
resource "aws_iam_role_policy_attachment" "knfsd_instance_role_netapp_exports_policy" {
  count      = local.netapp_enabled && var.EXISTING_INSTANCE_PROFILE_NAME == "" ? 1 : 0
  role       = aws_iam_role.knfsd_instance_role[0].name
  policy_arn = aws_iam_policy.knfsd_instance_role_netapp_exports_policy[0].arn
}

# Ensure the required service-linked roles exist. The AWSServiceRoleForAutoScaling
# SLR is always needed because the module always deploys an EC2 Auto Scaling group,
# while AWSServiceRoleForElasticLoadBalancing is only needed in "loadbalancer" mode.
# These SLRs are typically missing in a new AWS account that has never used EC2 ASG
# or Elastic Load Balancing. Deploy roles that lack iam:CreateServiceLinkedRole
# cannot create these SLRs, so this module never attempts creation; it only verifies
# presence and fails early with a clear remedy via AWS CLI.
data "aws_iam_roles" "autoscaling_slr" {
  name_regex  = "^AWSServiceRoleForAutoScaling$"
  path_prefix = "/aws-service-role/autoscaling.amazonaws.com/"
}

resource "null_resource" "autoscaling_slr_check" {
  lifecycle {
    precondition {
      condition     = length(data.aws_iam_roles.autoscaling_slr.names) > 0
      error_message = "This module requires the AWSServiceRoleForAutoScaling service-linked role, which is missing in this AWS account. Create it once with: aws iam create-service-linked-role --aws-service-name autoscaling.amazonaws.com"
    }
  }
}

data "aws_iam_roles" "elb_slr" {
  count       = var.TRAFFIC_MODE == "loadbalancer" ? 1 : 0
  name_regex  = "^AWSServiceRoleForElasticLoadBalancing$"
  path_prefix = "/aws-service-role/elasticloadbalancing.amazonaws.com/"
}

resource "null_resource" "elb_slr_check" {
  count = var.TRAFFIC_MODE == "loadbalancer" ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(data.aws_iam_roles.elb_slr[0].names) > 0
      error_message = "TRAFFIC_MODE=\"loadbalancer\" requires the AWSServiceRoleForElasticLoadBalancing service-linked role, which is missing in this AWS account. Create it once with: aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com"
    }
  }
}
