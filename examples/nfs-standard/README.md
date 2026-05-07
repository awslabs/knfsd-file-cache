# Standard NFS Example

This example shows a standard KNFSD proxy deployment.

As a starting point, the example deploys 3 KNFSD proxy instances with local NVMe.

The deployment uses an external Amazon RDS PostgreSQL database to store FSIDs to ensure all instances in the cluster allocate the same FSID to each export.

There are a number of ways to [monitor](../../docs/check-startup.md) the deployment progress.

## Security Groups

You will need to create or append to existing security group(s) for:

* NFS traffic; proxy to source
* NFS traffic; clients to proxy

See [Security Groups](../../deployment/docs/security-groups.md).

## Inputs

* `REGION` - (Required) The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`. No default.

* `SUBNET` - (Required) The single subnet ID to use for deployment of the KNFSD File Cache. Example: `subnet-038e337f0ff4cd53f`. No default.

* `PROXY_AMI` - (Required) The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script. No default.

* `EXPORT_MAP` - (Required) A list of NFS exports to mount from the source and re-export in the format `<SOURCE_IP>;<SOURCE_EXPORT>;<TARGET_EXPORT>`. See [KNFSD Deployment](../../deployment/README.md) for more details. No default.

* `PROXY_BASENAME` - (Optional) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). Default: `knfsd`.

* `KEY_NAME` - (Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: `""`.

## Outputs

* `autoscaling_group_name` - Name of the KNFSD proxy Auto Scaling Group.

* `autoscaling_group_security_group_id` - Security Group ID for the KNFSD proxy Auto Scaling Group.

* `database_config` - Database configuration for deployed RDS PostgreSQL database. Only available when database is deployed by this module (when `FSID_MODE` is `external`).

* `database_iam_policy` - The ARN of the IAM policy for `rds-db:connect` database access. Only available when database is deployed by this module (when `FSID_MODE` is `external`).

* `dns_name` - The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`).

* `loadbalancer_ipaddress` - The private IP address of the Network Load Balancer (when `TRAFFIC_MODE = "loadbalancer"`).

* `knfsd_security_group_id` - Security Group ID for the NFS clients to connect to the KNFSD proxy instances (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`).
