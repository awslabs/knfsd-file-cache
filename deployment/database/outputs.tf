# Copyright 2022 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "db_iam_policy" {
  description = "The ARN of the IAM policy for DynamoDB table access."
  value       = local.db_iam_policy_arn
}

output "region" {
  description = "The AWS region hosting the DynamoDB table."
  value       = local.region
}

output "table_name" {
  description = "The name of the DynamoDB table storing the FSID mappings."
  value       = aws_dynamodb_table.fsids.name
}
