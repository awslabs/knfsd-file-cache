# Basic NFS Example

This example provides a very simple, minimal deployment.

## Quick Deploy

The `PROXY_AMI` variable has no default, so you must first build the KNFSD proxy AMI with Packer, and pass the resulting AMI ID into `PROXY_AMI`.

See [KNFSD AMI Build](../../image/README.md) for the build instructions. The AMI must exist in the same AWS region as `REGION`.

Once you have built the KNFSD proxy AMI, you can deploy this basic example, providing your own values for the `REGION`, `SUBNET`, and `EXPORT_MAP` variables using the following commands:

```bash
cd knfsd-file-cache/examples/basic
terraform init
terraform apply \
  -var 'REGION=us-east-1' \
  -var 'SUBNET=subnet-038e337f0ff4cd53f' \
  -var 'PROXY_AMI=ami-0a1b2c3d4e5f6a7b8' \
  -var 'EXPORT_MAP=10.0.5.5;/assets;/assetscache,10.0.5.5;/textures;/texturescache'
```

In this fake source server example, the `EXPORT_MAP` values above mount `/assets` and `/textures` from the source server `10.0.5.5`, and re-export them from the proxy as `/assetscache` and `/texturescache`.

Single quotes are required so the shell does not interpret the `;` separators.

As an alternative to `-var` flags, place the same values in a `terraform.tfvars` file alongside `main.tf`, then run `terraform init` and `terraform apply` with no arguments:

```hcl
REGION     = "us-east-1"
SUBNET     = "subnet-038e337f0ff4cd53f"
PROXY_AMI  = "ami-0a1b2c3d4e5f6a7b8"
EXPORT_MAP = "10.0.5.5;/assets;/assetscache,10.0.5.5;/textures;/texturescache"
```

There are a number of ways to [monitor](../../docs/check-startup.md) the deployment progress.

## Security Groups

You will need to create or append to existing security group(s) for:

* NFS traffic; proxy to source
* NFS traffic; clients to proxy

See [Security Groups](../../deployment/docs/security-groups.md).

## Inputs

| Variable         | Description                                                                                                                         | Required | Default    |
|------------------|-------------------------------------------------------------------------------------------------------------------------------------|----------|------------|
| `REGION`         | The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`.                                                 | True     | No default |
| `SUBNET`         | The single subnet ID to use for deployment of the KNFSD File Cache. Example: `subnet-038e337f0ff4cd53f`.                            | True     | No default |
| `PROXY_AMI`      | The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script.   | True     | No default |
| `EXPORT_MAP`     | A list of NFS exports to mount from the source and re-export in the format `<SOURCE_IP>;<SOURCE_EXPORT>;<TARGET_EXPORT>`. *         | True     | No default |
| `PROXY_BASENAME` | Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a globally, unique basename to avoid conflicts. | False    | `knfsd`    |

\* See [KNFSD Deployment](../../deployment/README.md) for more details.

## Outputs

| Output                                | Description                                                                    |
|---------------------------------------|--------------------------------------------------------------------------------|
| `autoscaling_group_name`              | Name of the KNFSD proxy Auto Scaling Group.                                    |
| `autoscaling_group_security_group_id` | Security Group ID for the KNFSD proxy Auto Scaling Group.                      |
| `dns_name`                            | The private DNS name of the KNFSD proxy Auto Scaling Group.                    |
| `knfsd_security_group_id`             | Security Group ID for the NFS clients to connect to the KNFSD proxy instances. |
