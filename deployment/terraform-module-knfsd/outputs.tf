# Copyright 2020 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

output "autoscaling_group_name" {
  description = "Name of the KNFSD proxy Auto Scaling Group."
  value       = aws_autoscaling_group.knfsd_asg.name
}

output "autoscaling_group_security_group_id" {
  description = "Security Group ID for the KNFSD proxy Auto Scaling Group."
  value       = local.knfsd_sg_id
}

output "cluster_ready" {
  description = "Boolean indicating if all KNFSD instances are ready and fully operational. Use this as a dependency for downstream resources."
  value       = var.ENABLE_STATUS_CHECK ? true : null
  depends_on  = [null_resource.status_check]
}

output "database_config" {
  description = "Database configuration for the deployed DynamoDB FSID table. Only available when database is deployed by this module."
  value = local.deploy_fsid_database ? {
    table_name     = module.fsid_database[0].table_name
    region         = module.fsid_database[0].region
    enable_metrics = var.ENABLE_METRICS
  } : {}
}

output "database_iam_policy" {
  description = "The ARN of the IAM policy for DynamoDB table access. Only available when database is deployed by this module."
  value       = local.deploy_fsid_database ? module.fsid_database[0].db_iam_policy : null
}

output "dns_name" {
  description = "The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group."
  value = (
    var.TRAFFIC_MODE == "loadbalancer" ? one(module.loadbalancer[*].dns_name) :
    var.TRAFFIC_MODE == "dns_round_robin" ? one(module.dns_round_robin[*].dns_name) :
    null
  )
}

output "iam_role_name" {
  description = "Name of the IAM role attached to the KNFSD proxy instances. Null when EXISTING_INSTANCE_PROFILE_NAME is provided (the module does not create or manage the role in that case)."
  value       = var.EXISTING_INSTANCE_PROFILE_NAME == "" ? aws_iam_role.knfsd_instance_role[0].name : null
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile attached to the KNFSD proxy instances. Returns the module-created profile name, or the user-provided EXISTING_INSTANCE_PROFILE_NAME when set."
  value       = local.knfsd_instance_profile_name
}

output "loadbalancer_ipaddress" {
  description = "The private IP address of the Network Load Balancer."
  value       = one(module.loadbalancer[*].ip_address)
}

output "knfsd_security_group_id" {
  description = "Security Group ID for the NFS clients to connect to the KNFSD proxy instances."
  value = (
    var.TRAFFIC_MODE == "loadbalancer" ? one(module.loadbalancer[*].lb_security_group_id) :
    var.TRAFFIC_MODE == "dns_round_robin" ? local.knfsd_sg_id :
    null
  )
}
