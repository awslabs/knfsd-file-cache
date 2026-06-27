# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Minimal IAM instance profile for the smoke-test NFS client EC2 instance.
# Grants AWS Systems Manager Session Manager access (AmazonSSMManagedInstanceCore)
# so the Go driver can reach the instance over SSH-over-SSM, plus a scoped
# self-tagging policy used to publish the "knfsd-file-cache:status" tag.

# get the current AWS partition (aws, aws-us-gov, aws-cn)
data "aws_partition" "current" {}

# get the current AWS account id
data "aws_caller_identity" "current" {}

resource "aws_iam_instance_profile" "client" {
  name = "${var.PREFIX}-client-instance-profile"
  role = aws_iam_role.client.name
  tags = {
    "knfsd-file-cache:run"       = var.PREFIX
    "knfsd-file-cache:component" = "nfs-client"
  }
}

resource "aws_iam_role" "client" {
  name        = "${var.PREFIX}-client-instance-role"
  description = "IAM role for smoke-test client EC2 instance"
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
  tags = {
    "knfsd-file-cache:run"       = var.PREFIX
    "knfsd-file-cache:component" = "nfs-client"
  }
}

resource "aws_iam_role_policy_attachment" "client_ssm_core" {
  role       = aws_iam_role.client.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM policy document for self-tagging the instance "knfsd-file-cache:status" tag
data "aws_iam_policy_document" "client_ec2_instance_tags" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags", "ec2:DescribeTags"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.REGION}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_policy" "client_ec2_instance_tags" {
  name   = "${var.PREFIX}-client-ec2-instance-tags-policy"
  policy = data.aws_iam_policy_document.client_ec2_instance_tags.json
}

resource "aws_iam_role_policy_attachment" "client_ec2_instance_tags" {
  role       = aws_iam_role.client.name
  policy_arn = aws_iam_policy.client_ec2_instance_tags.arn
}
