# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "endpoint_service_names" {
  description = "Resolved partition-correct service names for every endpoint created, for auditing which endpoints exist. Empty map if no endpoints are created."
  value = merge(
    try({ for k, v in aws_vpc_endpoint.knfsd_endpoints : k => v.service_name }, {}),
    try({ dynamodb = aws_vpc_endpoint.knfsd_dynamodb.service_name }, {}),
    try({ for k, v in aws_vpc_endpoint.knfsd_cross_region_endpoints : k => v.service_name }, {}),
    try({ for k, v in aws_vpc_endpoint.knfsd_global_endpoints : k => v.service_name }, {}),
  )
}

output "endpoints_ready" {
  description = "Boolean confirming every expected endpoint (regional interface + global + DynamoDB gateway) was created. A quick success signal for the deployment. False if the expected endpoint set cannot be determined."
  value = try(
    length(aws_vpc_endpoint.knfsd_endpoints) == length(local.services) &&
    length(local.cross_region_services) + length(local.same_region_global_services) == length(local.global_services) &&
    aws_vpc_endpoint.knfsd_dynamodb.state == "available",
    false
  )
}

output "security_group_id" {
  description = "ID of the security group attached to all KNFSD interface VPC endpoints. Returns the module-created security group, or EXISTING_SECURITY_GROUP_ID when set."
  value       = local.vpc_endpoints_sg_id
}
