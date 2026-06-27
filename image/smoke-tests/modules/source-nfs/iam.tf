# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Minimal IAM instance profile for the source-NFS EC2 instance. Grants only
# AWS Systems Manager Session Manager access (AmazonSSMManagedInstanceCore)
# so operators can attach a shell to the instance for emergency debugging
# without widening the SG ingress rules. Future FIO/CloudWatch publishing
# can extend this role with an additional inline policy.

# get the current AWS partition (aws, aws-us-gov, aws-cn)
data "aws_partition" "current" {}

# get the current AWS account id
data "aws_caller_identity" "current" {}

resource "aws_iam_instance_profile" "source" {
  name = "${var.NAME}-instance-profile"
  role = aws_iam_role.source.name
  tags = var.TAGS
}

resource "aws_iam_role" "source" {
  name        = "${var.NAME}-instance-role"
  description = "IAM role for source-NFS test instance"
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
  tags                  = var.TAGS
}

resource "aws_iam_role_policy_attachment" "source_ssm_core" {
  role       = aws_iam_role.source.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM policy document for self-tagging the instance "knfsd-file-cache:status" tag
data "aws_iam_policy_document" "source_ec2_instance_tags" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags", "ec2:DescribeTags"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.REGION}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_policy" "source_ec2_instance_tags" {
  name   = "${var.NAME}-ec2-instance-tags-policy"
  policy = data.aws_iam_policy_document.source_ec2_instance_tags.json
  tags   = var.TAGS
}

resource "aws_iam_role_policy_attachment" "source_ec2_instance_tags" {
  role       = aws_iam_role.source.name
  policy_arn = aws_iam_policy.source_ec2_instance_tags.arn
}
