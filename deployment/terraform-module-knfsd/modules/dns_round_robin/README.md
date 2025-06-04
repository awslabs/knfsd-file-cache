# KNFSD DNS Round Robin Module

This Terraform module configures Amazon Route 53 DNS to use DNS round-robin for a KNFSD proxy cluster. This offers an alternative to using the load balancer by deploying a Lambda function to create/delete or modify a secondary ENI (static IP) for each EC2 instance in the ASG of the KNFSD proxy cluster.

This module is not intended to be used directly, and is deployed by the main KNFSD proxy module only when `TRAFFIC_MODE = "dns_round_robin"`.

## Prerequisites

To use DNS round-robin the KNFSD proxy cluster must be configured with:

* `ENABLE_KNFSD_AUTOSCALING = false`
* `TRAFFIC_MODE = "dns_round_robin"`

## Inputs

* `SUBNET` - (Required) The single subnet ID to use for deployment of the KNFSD solution. Example: "subnet-038e337f0ff4cd53f". No default.

* `PROXY_BASENAME` - (Required) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). No default.

* `DNS_NAME` - (Optional) The fully qualified domain name (FQDN) to assign the KNFSD proxy cluster. Defaults to: `{PROXY_BASENAME}.knfsd.internal.` [Note: the trailing period is required]. Default: "".

## Outputs

* `dns_name` - The DNS name that was created for the KNFSD proxy cluster.

    > NOTE: `dns_name` is useful if you're creating other resources in the same Terraform configuration that depend on the DNS entry to create a dependency between the DNS entry and the other resources.

* `lambda_static_ip_resources` - [internal] Resources for the Lambda 'static_ip' function dependency.

    > NOTE: The `lambda_static_ip_resources` output is used to ensure that the Lambda 'static_ip' function is destroyed after the ASG is deleted.
