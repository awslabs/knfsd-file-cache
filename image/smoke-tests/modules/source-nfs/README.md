# Source NFS Filer Module

This Terraform module provisions a single EC2 instance configured as an NFS v3/v4 source server, intended for use as the upstream filer in KNFSD test scenarios.

The instance:

- Uses local NVMe instance storage (default `i3en.large`, override with `INSTANCE_TYPE` to use `im4gn.*` for arm64 or larger storage variants).
- Is partitioned and formatted as XFS by the user-data startup script.
- Exports `/files` via NFS to the **VPC CIDR** of the subnet it lives in.
- Has IMDSv2 enforced (`http_tokens = "required"`) and `instance_metadata_tags = "enabled"` so the startup script can read its own configuration tags.
- Optionally applies `tc qdisc netem` for latency / bandwidth shaping (driven by the `LATENCY_MS` / `RATE_LIMIT_MBIT` variables).

## Usage

```hcl
module "source_nfs" {
  source            = "./modules/source-nfs"
  REGION            = "us-east-1"
  NAME              = "knfsd-smoke-source-${random_id.run.hex}"
  SUBNET            = var.SUBNET
  SECURITY_GROUP_ID = aws_security_group.source_nfs.id
  LATENCY_MS        = 0
  RATE_LIMIT_MBIT   = 0
}
```

## Inputs

| Name                          | Description                                          | Type          | Default        |
|-------------------------------|------------------------------------------------------|---------------|----------------|
| `REGION`                      | AWS region.                                          | `string`      | n/a            |
| `NAME`                        | EC2 Name tag.                                        | `string`      | n/a            |
| `SUBNET`                      | Subnet ID (its VPC CIDR is used for the NFS export). | `string`      | n/a            |
| `SECURITY_GROUP_ID`           | Security group to attach.                            | `string`      | n/a            |
| `ASSOCIATE_PUBLIC_IP_ADDRESS` | Force a public IP (`null` = inherit subnet setting). | `bool`        | `false`        |
| `INSTANCE_TYPE`               | EC2 instance type with local NVMe.                   | `string`      | `"i3en.large"` |
| `AMI_ID`                      | Override AMI ID. Auto-resolved from SSM if empty.    | `string`      | `""`           |
| `ARCH`                        | `amd64` or `arm64` (used to resolve default AMI).    | `string`      | `"amd64"`      |
| `ROOT_VOLUME_SIZE_GB`         | Root EBS volume size.                                | `number`      | `20`           |
| `LATENCY_MS`                  | tc netem delay in ms. 0 disables.                    | `number`      | `0`            |
| `RATE_LIMIT_MBIT`             | tc netem rate in MBit. 0 disables.                   | `number`      | `0`            |
| `TAGS`                        | Extra tags.                                          | `map(string)` | `{}`           |

## Outputs

| Name          | Description                                 |
|---------------|---------------------------------------------|
| `instance_id` | EC2 instance ID.                            |
| `private_ip`  | Private IPv4 address.                       |
| `private_dns` | Private DNS name.                           |
| `nfs_share`   | Combined `<ip>:/files` share path.          |
| `vpc_cidr`    | VPC CIDR used for the NFS export allowlist. |
