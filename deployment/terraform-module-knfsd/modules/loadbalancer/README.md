# KNFSD Proxy Load Balancer Module

This module supports deploying a Network Load Balancer TCP/UDP for the KNFSD proxy cluster.

This module is not generally intended to be used directly, and is included by the main KNFSD proxy module when `TRAFFIC_MODE = "loadbalancer"`.

## Prerequisites

These prerequisites are normally created by the main KNFSD proxy module.

## Inputs

| Name                         | Description                                                                                                                                               | Required | Default                              |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|----------|--------------------------------------|
| `SUBNET`                     | The subnet ID to use for deployment of the Network Load Balancer. Example: "subnet-038e337f0ff4cd53f".                                                    | True     | No default                           |
| `PROXY_BASENAME`             | Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a globally unique basename to avoid conflicts within an AWS account.  | True     | No default                           |
| `DNS_NAME`                   | The fully qualified DNS name (FQDN) to use for the KNFSD proxy cluster. [Note: the trailing period is required].                                          | False    | `nlb.{PROXY_BASENAME}.aws.internal.` |
| `NFS_PORTS`                  | The list of NFS ports (TCP & UDP) to use with the Network Load Balancer.                                                                                  | True     | See `variables.tf` for TCP/UDP ports |
| `VPC_CIDR`                   | List of CIDR blocks to allow in security group ingress/egress rules.                                                                                      | True     | No default                           |
| `LOADBALANCER_IP`            | The static private IPv4 address to use for the Network Load Balancer. If not specified, a random IP address will be assigned from the subnet.             | False    | `null`                               |
| `EXISTING_SECURITY_GROUP_ID` | ID of a pre-existing security group to use for the Network Load Balancer instead of creating one. When set, the module skips creating the security group. | False    | `""`                                 |

## Outputs

| Name                   | Description                                                                |
|------------------------|----------------------------------------------------------------------------|
| `dns_name`             | The private DNS name that was created for the KNFSD Network Load Balancer. |
| `ip_address`           | The private IP address of the KNFSD Network Load Balancer.                 |
| `lb_security_group_id` | The ID of the KNFSD Network Load Balancer Security Group.                  |
| `lb_target_groups`     | Map of NFS port names to target group ARNs.                                |
