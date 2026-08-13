# Copyright 2020 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

module "loadbalancer" {
  count                           = var.TRAFFIC_MODE == "loadbalancer" ? 1 : 0
  source                          = "./modules/loadbalancer"
  SUBNET                          = var.SUBNET
  PROXY_BASENAME                  = local.name
  DNS_NAME                        = var.DNS_NAME
  LOADBALANCER_IP                 = var.LOADBALANCER_IP
  NFS_PORTS                       = var.NFS_PORTS
  VPC_CIDR                        = local.vpc_cidr
  HEALTHCHECK_INTERVAL_SECONDS    = var.HEALTHCHECK_INTERVAL_SECONDS
  HEALTHCHECK_TIMEOUT_SECONDS     = var.HEALTHCHECK_TIMEOUT_SECONDS
  HEALTHCHECK_HEALTHY_THRESHOLD   = var.HEALTHCHECK_HEALTHY_THRESHOLD
  HEALTHCHECK_UNHEALTHY_THRESHOLD = var.HEALTHCHECK_UNHEALTHY_THRESHOLD
  EXISTING_SECURITY_GROUP_ID      = var.EXISTING_SECURITY_GROUP_ID
}

resource "null_resource" "dns_round_robin" {
  count = var.TRAFFIC_MODE == "dns_round_robin" ? 1 : 0
  lifecycle {
    precondition {
      condition     = !var.ENABLE_KNFSD_AUTOSCALING
      error_message = "ENABLE_KNFSD_AUTOSCALING cannot be enabled when using DNS round robin."
    }
  }
}

module "dns_round_robin" {
  count                    = var.TRAFFIC_MODE == "dns_round_robin" ? 1 : 0
  source                   = "./modules/dns_round_robin"
  SUBNET                   = var.SUBNET
  PROXY_BASENAME           = local.name
  DNS_NAME                 = var.DNS_NAME
  EXISTING_LAMBDA_ROLE_ARN = var.EXISTING_LAMBDA_ROLE_ARN
  depends_on               = [null_resource.dns_round_robin]
}
