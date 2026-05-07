# IAM Permissions

The AWS KNFSD-File-Cache solution requires IAM permissions for two phases:

1. **Packer build** - building the KNFSD AMI from `image/`.
2. **Terraform deployment** - deploying the KNFSD proxy cluster from `deployment/`.

The canonical, region-agnostic IAM policies live under [iam/](iam/) and are split into three standalone customer-managed-policy-attachable JSON files.

The two phases can use a single combined IAM principal for simple setups, or be split across separate principals (one for AMI builds, one for deployments) for stronger separation of duties.

> INFO: These IAM policies do not cover any additional IAM requirements for the KNFSD File Cache [`examples/`](../examples/).

## Files at a glance

| File               | Status            | Description                                                                                                                                                                              |
| ------------------ | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packer.json`      | AMI build         | Standalone IAM policy for `packer build` in [`image/`](../image/).                                                                                                                       |
| `tf-required.json` | Deploy (required) | Always-required Sids for `terraform apply` in [`deployment/`](../deployment/).                                                                                                           |
| `tf-optional.json` | Deploy (deps)     | Feature-gated Sids; attach only when `var.FSID_DATABASE_DEPLOY = true`, `var.ENABLE_NETAPP_AUTO_DETECT = true` (with `var.NETAPP_SECRET != ""`), or `var.TRAFFIC_MODE = "loadbalancer"`. |

## How to attach

* **AMI-build-only principal** - attach `iam/packer.json`.
* **Deploy-only principal** - attach `iam/tf-required.json` (required) and `iam/tf-optional.json` (only when at least one gating TF variable is in use).
* **Single combined principal that does both phases** - attach all three files.

## Required vs Optional Sids

`Status` values:

* **AMI build** - required by `packer build`.
* **Deploy (required)** - required by every `terraform apply` regardless of feature flags.
* **Deploy (deps)** - required only when the gating Terraform variable is set.

| Sid                             | File                             | Status            | Notes                                                                                                                                                             |
| ------------------------------- | -------------------------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `KnfsdPackerBuild`              | `packer.json`                    | AMI build         | EC2 + Spot fleet + describe actions.                                                                                                                              |
| `KnfsdPackerIamPassRole`        | `packer.json`                    | AMI build         | Passes the Packer instance profile to EC2 (scoped via `iam:PassedToService`).                                                                                     |
| `KnfsdPackerServiceLinkedRoles` | `packer.json`                    | AMI build         | Creates the Spot service-linked role on first use (scoped via `iam:AWSServiceName`).                                                                              |
| `KnfsdSsmPublicParameters`      | `packer.json`                    | AMI build         | Ubuntu base AMI lookup via `amazon-parameterstore`.                                                                                                               |
| `KnfsdKms`                      | `packer.json`,`tf-required.json` | Deploy (required) | Encrypted EBS / AMI; cross-account KMS via `kms:CreateGrant` and `kms:DescribeKey`. Required for both phases.                                                     |
| `KnfsdCompute`                  | `tf-required.json`               | Deploy (required) | EC2 launch template, capacity reservation, KNFSD proxy security group, networking lookups, ASG instance polling for `ENABLE_STATUS_CHECK`.                        |
| `KnfsdAutoScaling`              | `tf-required.json`               | Deploy (required) | KNFSD Auto Scaling Group, scaling policies, lifecycle hooks.                                                                                                      |
| `KnfsdSsmParameters`            | `tf-required.json`               | Deploy (required) | KNFSD configuration in SSM Parameter Store under `/knfsd/*`.                                                                                                      |
| `KnfsdCloudWatch`               | `tf-required.json`               | Deploy (required) | CloudWatch alarms and dashboards.                                                                                                                                 |
| `KnfsdCloudFormation`           | `tf-required.json`               | Deploy (required) | `knfsd-metrics-dashboard` CloudFormation stack.                                                                                                                   |
| `KnfsdRoute53`                  | `tf-required.json`               | Deploy (required) | Required when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`; one of those modes is always selected, so this Sid is effectively always required.           |
| `KnfsdCloudWatchLogs`           | `tf-required.json`               | Deploy (required) | KNFSD log groups.                                                                                                                                                 |
| `KnfsdIamRoles`                 | `tf-required.json`               | Deploy (required) | KNFSD instance role + Lambda execution roles (including attach/detach managed policies, plus inline policies used by the RDS `db_setup` Lambda role).             |
| `KnfsdIamPolicies`              | `tf-required.json`               | Deploy (required) | KNFSD instance policies (EC2 tags, SSM access, etc).                                                                                                              |
| `KnfsdIamInstanceProfile`       | `tf-required.json`               | Deploy (required) | KNFSD instance profile.                                                                                                                                           |
| `KnfsdIamPassRole`              | `tf-required.json`               | Deploy (required) | Passes the KNFSD role to EC2, Lambda, and Auto Scaling.                                                                                                           |
| `KnfsdIamReadManagedPolicies`   | `tf-required.json`               | Deploy (required) | Reads AWS-managed policies attached to the KNFSD role.                                                                                                            |
| `KnfsdAsgServiceLinkedRole`     | `tf-required.json`               | Deploy (required) | Creates the Auto Scaling service-linked role on first use.                                                                                                        |
| `KnfsdAsgSlrCheck`              | `tf-required.json`               | Deploy (required) | `null_resource` precondition that verifies the Auto Scaling SLR is ready before the ASG is created.                                                               |
| `KnfsdLambda`                   | `tf-required.json`               | Deploy (deps)     | Required when `TRAFFIC_MODE = "dns_round_robin"` (default; `static_ip` Lambda for secondary ENIs) or when `FSID_DATABASE_DEPLOY = true`.                          |
| `KnfsdEventBridge`              | `tf-required.json`               | Deploy (deps)     | Required when `TRAFFIC_MODE = "dns_round_robin"` (default); Auto Scaling lifecycle event rules.                                                                   |
| `KnfsdRds`                      | `tf-optional.json`               | Deploy (deps)     | Required when `FSID_MODE = "external"` and `FSID_DATABASE_DEPLOY = true`; provisions the RDS PostgreSQL database for external FSIDs.                              |
| `KnfsdRdsPassRole`              | `tf-optional.json`               | Deploy (deps)     | Required when `FSID_DATABASE_DEPLOY = true`; passes the `knfsd-*-rds-enhanced-monitoring` role to RDS for Enhanced Monitoring.                                    |
| `KnfsdRdsManagedSecret`         | `tf-optional.json`               | Deploy (deps)     | Required when `FSID_DATABASE_DEPLOY = true`; allows RDS to create and tag the `rds!*` master user secret on the caller's behalf.                                  |
| `KnfsdRdsManagedSecretKms`      | `tf-optional.json`               | Deploy (deps)     | Required when `FSID_DATABASE_DEPLOY = true`; `kms:DescribeKey` on the AWS-managed key used to encrypt the RDS master user secret.                                 |
| `KnfsdSecretsManager`           | `tf-optional.json`               | Deploy (deps)     | Required when `FSID_DATABASE_DEPLOY = true` (RDS master credentials) or `ENABLE_NETAPP_AUTO_DETECT = true` with `NETAPP_SECRET != ""` (NetApp ONTAP credentials). |
| `KnfsdVpcEndpoints`             | `tf-optional.json`               | Deploy (deps)     | Required when `FSID_DATABASE_DEPLOY = true`; creates the Secrets Manager VPC endpoint and reads its prefix list.                                                  |
| `KnfsdElbServiceLinkedRole`     | `tf-optional.json`               | Deploy (deps)     | Required when `TRAFFIC_MODE = "loadbalancer"`; creates the Elastic Load Balancing service-linked role on first use.                                               |
| `KnfsdLoadBalancer`             | `tf-optional.json`               | Deploy (deps)     | Required when `TRAFFIC_MODE = "loadbalancer"`; manages the Network Load Balancer, target groups, and listeners.                                                   |

## Narrowing scope with Conditions

The IAM policies are intentionally region-agnostic. Add an `aws:RequestedRegion` Condition to restrict a policy to a single region or a list of regions. Apply the Condition to every Sid that you want to scope:

```json
{
    "Sid": "KnfsdCompute",
    "Effect": "Allow",
    "Action": [
        "ec2:CreateLaunchTemplate"
    ],
    "Resource": "*",
    "Condition": {
        "StringEquals": {
            "aws:RequestedRegion": ["us-east-1"]
        }
    }
}
```

Refer to the [AWS global condition keys reference](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html) for the full list.

## Naming-prefix recommendation

Several Sids scope their `Resource` ARNs to `knfsd-*` (CloudFormation, Lambda, EventBridge, IAM roles/policies/instance-profiles, Secrets Manager, CloudWatch Logs). This requires deployed resource names to start with `knfsd-`.

The default values aligning with the canonical policies are:

* `var.PROXY_BASENAME` defaults to `knfsd` (from `terraform-module-knfsd/variables.tf`). The module's `local.name` fallback prefixes the random hex with `knfsd-` so the result is always `knfsd-<hex>`.
* `var.NAME_PREFIX` in the database module defaults to `knfsd-fsids`.

If you override these Terraform variables, ensure the override starts with `knfsd-` (or update the `Resource` ARNs in your local copy of the IAM policies to match).
