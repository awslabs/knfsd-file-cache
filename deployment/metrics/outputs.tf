# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "dashboard_arn" {
  description = "The Amazon Resource Name (ARN) of the created CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.knfsd_monitoring_dashboard.dashboard_arn
}

output "dashboard_name" {
  description = "Name of the created CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.knfsd_monitoring_dashboard.dashboard_name
}
