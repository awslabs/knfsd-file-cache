# Amazon EFS Example

Amazon Elastic File System ([Amazon EFS](https://docs.aws.amazon.com/efs/latest/ug/features.html)) is a simple, serverless, set-and-forget, elastic file system that supports NFSv4.1.

This example provides a single KNFSD proxy connecting to a single-AZ (One Zone) Amazon EFS filesystem to act as the source filer. We enforce NFS v4.1 throughout the deployment, as EFS does not support NFS v3 or v4.2.

For simplicity this example uses some settings that are not recommended for production:

* `FSID_MODE = "static"`

This deploys the KNFSD proxy cluster without a shared FSID database. In production it is recommended to use a shared (`"external"`) FSID database to ensure that all the KNFSD proxy instances in the cluster allocate the same FSID to each export.

## EFS Utilities

Amazon EFS does not support the `nconnect` option, which is required for high-performance NFS workloads. Instead, the [amazon-efs-utils](https://github.com/aws/efs-utils) package (already installed via the Packer image build) provides a `mount` helper and proxy to provide higher per-client throughput, due to the way EFS scales out the access layer.

## Mounting EFS

EFS does not support the `showmount` command, so we must identify the filesystem type when we wish to mount an EFS filesystem via the `EXPORT_MAP` variable, which is handled automatically in this canned example as we programmatically create the EFS filesystem. We add a 4th argument to the `EXPORT_MAP` variable to identify the `<FILESYSTEM_TYPE>` as `efs` to force the `mount.efs` helper to be used.

```hcl
<SOURCE_DNS>;<SOURCE_EXPORT>;<TARGET_EXPORT>;<FILESYSTEM_TYPE>
```

See `man mount.efs` for additional mount options specific to EFS that can be provided via the `var.MOUNT_OPTIONS` variable.

There are a number of ways to [monitor](../../docs/check-startup.md) the deployment progress.

## Security Groups

This example creates a dedicated security group for the EFS mount target (proxy to source), allowing inbound NFS traffic from the proxy ASG security group.

You will need to create or append to existing security group(s) for:

* NFS traffic; clients to proxy

See [Security Groups](../../deployment/docs/security-groups.md).

## IAM Permissions

This example creates Amazon EFS resources (`aws_efs_file_system`, `aws_efs_backup_policy`, `aws_efs_mount_target`) that are not covered by the project-wide IAM policies under [docs/iam/](../../docs/iam/). The additional `elasticfilesystem:*` permissions required to deploy this example are provided in [iam.json](iam.json) and should be attached to the same principal that runs `terraform apply` for this example, alongside [docs/iam/tf-required.json](../../docs/iam/tf-required.json) (and [docs/iam/tf-optional.json](../../docs/iam/tf-optional.json) when applicable). See [docs/iam.md](../../docs/iam.md) for the full IAM reference.

## Inputs

* `REGION` - (Required) The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`. No default.

* `SUBNET` - (Required) The single subnet ID to use for deployment of the KNFSD File Cache. Example: `subnet-038e337f0ff4cd53f`. No default.

* `PROXY_AMI` - (Required) The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script. No default.

* `PROXY_BASENAME` - (Optional) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). Default: `knfsd`.

* `KEY_NAME` - (Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: `""`.

* `INSTANCE_TYPE` - (Optional) The AWS EC2 instance type to use for the KNFSD cache. Default: `i3en.6xlarge`.

* `KNFSD_NODES` - (Optional) The number of KNFSD instances to deploy as part of the cluster. Default: `1`.

## Outputs

* `autoscaling_group_name` - Name of the KNFSD proxy Auto Scaling Group.

* `autoscaling_group_security_group_id` - Security Group ID for the KNFSD proxy Auto Scaling Group.

* `dns_name` - The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`).

* `loadbalancer_ipaddress` - The private IP address of the Network Load Balancer (when `TRAFFIC_MODE = "loadbalancer"`).

* `knfsd_security_group_id` - Security Group ID for the NFS clients to connect to the KNFSD proxy instances (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`).

## Amazon EFS Limitations

Amazon EFS does not support being re-exported more than once, so does not support the `fanout` feature. You will see a "stale file handle" error on the 2nd tier KNFSD proxy, with a loss of metadata on the 1st and 2nd tier KNFSD proxies.
