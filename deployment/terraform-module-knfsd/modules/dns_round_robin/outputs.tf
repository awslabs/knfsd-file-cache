/*
 * Copyright 2020 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "dns_name" {
  description = "The DNS name that was created for the KNFSD proxy cluster."
  # Even when setting var.DNS_NAME explicitly this is still useful as it
  # allows other resources to reference the DNS zone name
  value = var.DNS_NAME == "" ? aws_route53_zone.knfsd[0].name : trimsuffix(var.DNS_NAME, ".")
}

output "lambda_static_ip_resources" {
  description = "Resources for the Lambda 'static_ip' function dependency."
  value = {
    lambda_function                   = aws_lambda_function.static_ip.arn
    lambda_log_group                  = aws_cloudwatch_log_group.lambda_static_ip.arn
    lambda_iam_role                   = aws_iam_role.lambda_static_ip.arn
    lambda_iam_policy                 = aws_iam_policy.lambda_static_ip.arn
    lambda_iam_role_policy_attachment = aws_iam_role_policy_attachment.lambda_static_ip.id
    cw_event_rule_launching           = aws_cloudwatch_event_rule.instance_launching.arn
    cw_event_rule_terminated          = aws_cloudwatch_event_rule.instance_terminated.arn
    cw_target_launching               = aws_cloudwatch_event_target.instance_launching_target.arn
    cw_target_terminated              = aws_cloudwatch_event_target.instance_terminated_target.arn
    allow_eventbridge_launching       = aws_lambda_permission.allow_eventbridge_launching.id
    allow_eventbridge_terminated      = aws_lambda_permission.allow_eventbridge_terminated.id
  }
}
