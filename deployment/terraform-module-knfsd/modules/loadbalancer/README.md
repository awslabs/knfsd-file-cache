# KNFSD Proxy Load Balancer Module

This module supports deploying a Network Load Balancer TCP/UDP for the KNFSD proxy cluster.

This module is not generally intended to be used directly, and is included by the main KNFSD proxy module when `TRAFFIC_MODE = "loadbalancer"`.

## Prerequisites

These prerequisites are normally created by the main KNFSD proxy module.

## Inputs

* `SUBNET` - (Required) The subnet ID to use for deployment of the Network Load Balancer. Example: "subnet-038e337f0ff4cd53f".

* `PROXY_BASENAME` - (Required) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account).

* `DNS_NAME` - (Optional) The fully qualified DNS name (FQDN) to use for the KNFSD proxy cluster. Defaults to: `lb-knfsd.{PROXY_BASENAME}.aws.internal.` [Note: the trailing period is required].

* `NFS_PORTS` - (Required) The list of NFS ports (TCP & UDP) to use with the Network Load Balancer.

* `VPC_CIDR` - (Required) List of CIDR blocks to allow in security group ingress/egress rules.

* `LOADBALANCER_IP` - (Optional) The static private IPv4 address to use for the Network Load Balancer. If not specified, a random IP address will be assigned from the subnet.

## Outputs

* `dns_name` - The private DNS name that was created for the KNFSD Network Load Balancer.

* `ip_address` - The private IP address of the KNFSD Network Load Balancer.

* `lb_security_group_id` - The ID of the KNFSD Network Load Balancer Security Group.

* `lb_target_groups` - Map of NFS port names to target group ARNs.
