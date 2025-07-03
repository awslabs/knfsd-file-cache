# Basic NFS Example

This example provides a very simple, minimal deployment.

This can be used to verify that the KNFSD caching proxy can be deployed, and can connect to the source NFS server.

For simplicity this example uses some settings that are not recommended for production:

* `FSID_MODE = "static"`

This deploys the KNFSD proxy cluster without a shared FSID database.

In production it is recommended to use a shared (external) FSID database to ensure that all the KNFSD proxy instances in the cluster allocate the same FSID to each export.

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

* `PROXY_BASENAME` - (Optional) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). Default: `nfsproxy`.

* `KEY_NAME` - (Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: `""`.

## Outputs

* `autoscaling_group_name` - Name of the KNFSD proxy Auto Scaling Group.

* `proxy_host` - DNS name of the KNFSD proxy.
