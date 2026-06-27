# Copyright 2022 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
output "db_address" {
  description = "The hostname of the RDS DB instance."
  value       = aws_db_instance.fsids.address
}

output "db_iam_policy" {
  description = "The ARN of the IAM policy for rds-db:connect database access."
  value       = aws_iam_policy.db_policy.arn
}

output "db_name" {
  description = "The name of the PostgreSQL database."
  value       = aws_db_instance.fsids.db_name
}

output "db_port" {
  description = "The port of the RDS DB instance."
  value       = aws_db_instance.fsids.port
}

output "db_user" {
  description = "The DB username to access the PostgreSQL database."
  value       = local.db_user
}

output "master_username" {
  description = "The master username for the PostgreSQL database. Password is stored in AWS Secrets Manager."
  value       = aws_db_instance.fsids.username
}
