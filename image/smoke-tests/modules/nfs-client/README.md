# NFS Client Module

This Terraform module provisions a single Ubuntu EC2 instance configured as an NFS client, intended to run the compiled smoke-test `remote.test` binary against both the source NFS filer and the KNFSD proxy in KNFSD test scenarios.

The instance:

- Boots the latest Ubuntu 24.04 AMI resolved from SSM Parameter Store for the requested `ARCH` (validated against the `INSTANCE_TYPE` family).
- Installs `nfs-common` via the user-data startup script; no NFS mounts are performed at boot (the Go driver mounts on demand).
- Has IMDSv2 enforced (`http_tokens = "required"`) and `instance_metadata_tags = "enabled"` so the startup script can self-tag and the smoke-test driver can discover the source/proxy hosts.
- Surfaces the source NFS server and KNFSD proxy hosts to the driver via the `knfsd-file-cache:source-host` and `knfsd-file-cache:proxy-host` tags.
- Is reached keylessly by the Go driver over SSM (`AWS-StartSSHSession`) using an ephemeral EC2 Instance Connect key, so no ingress rule and no stored SSH key pair are required.

## Usage

```hcl
module "nfs_client" {
  source            = "./modules/nfs-client"
  REGION            = "us-east-1"
  SUBNET            = var.SUBNET
  SECURITY_GROUP_ID = aws_security_group.client.id
  PREFIX            = "knfsd-smoke-${random_id.run.hex}"
  SOURCE_HOST       = module.source_nfs.private_ip
  PROXY_HOST        = module.proxy.dns_name
  CLUSTER_READY     = module.proxy.cluster_ready
}
```

## Inputs

| Name                          | Description                                                                      | Type     | Default      |
|-------------------------------|----------------------------------------------------------------------------------|----------|--------------|
| `REGION`                      | AWS region.                                                                      | `string` | n/a          |
| `SUBNET`                      | Subnet ID the client instance is launched into.                                  | `string` | n/a          |
| `SECURITY_GROUP_ID`           | Security group to attach.                                                        | `string` | n/a          |
| `PREFIX`                      | Resource name prefix used to disambiguate parallel test runs.                    | `string` | n/a          |
| `SOURCE_HOST`                 | Source NFS host, surfaced via the `knfsd-file-cache:source-host` tag.            | `string` | n/a          |
| `PROXY_HOST`                  | KNFSD proxy DNS name, surfaced via the `knfsd-file-cache:proxy-host` tag.        | `string` | n/a          |
| `ARCH`                        | `amd64` or `arm64` (used to resolve the Ubuntu AMI). Must match `INSTANCE_TYPE`. | `string` | `"amd64"`    |
| `INSTANCE_TYPE`               | EC2 instance type. Must match `ARCH`.                                            | `string` | `"t3.small"` |
| `ASSOCIATE_PUBLIC_IP_ADDRESS` | Force a public IP (`null` = inherit subnet setting).                             | `bool`   | `null`       |
| `CLUSTER_READY`               | Dependency handle gating client creation until the proxy cluster is ready.       | `any`    | `null`       |

## Outputs

| Name          | Description           |
|---------------|-----------------------|
| `instance_id` | EC2 instance ID.      |
| `private_ip`  | Private IPv4 address. |
