# IAM Permissions

The AWS KNFSD-File-Cache solution requires IAM permissions for two phases:

1. **Packer build** - building the KNFSD AMI from `image/`.
2. **Terraform deployment** - deploying the KNFSD proxy cluster from `deployment/`.

The canonical, region-agnostic IAM policies live under [iam/](iam/) and are split into standalone customer-managed-policy-attachable JSON files.

The two phases can use a single combined IAM principal for simple setups, or be split across separate principals (one for AMI builds, one for deployments) for stronger separation of duties.

A separate policy, [`vpc-endpoints.json`](iam/vpc-endpoints.json), is **optional** and self-contained: it grants everything needed to deploy the standalone [`deployment/vpc-endpoints/`](../deployment/vpc-endpoints/) module (interface and gateway VPC endpoints plus their security group) with no reliance on the other `iam/` files. Attach it only when deploying that module, which some customers deploy separately (and often by a different principal) before the main cluster.

A further policy, [`testing.json`](iam/testing.json), is **not** required to build or deploy KNFSD. It grants the SSH-over-SSM / EC2 Instance Connect permissions used only by this repository's own test harness ([`image/smoke-tests/`](../image/smoke-tests/)) to reach the ephemeral test instances, plus the read-only DynamoDB actions (`dynamodb:GetItem`, `dynamodb:Scan`) the harness uses to assert the FSID mappings.

Two further policies, [`remote-ssh.json`](iam/remote-ssh.json) and [`remote-ssh-instance-profile.json`](iam/remote-ssh-instance-profile.json), are also **not** required to build or deploy KNFSD. They cover the optional developer cloud development environment (CDE) driven by the `.devcontainer/dev/remote.sh` and `.devcontainer/dev/run-fio-nfs.sh` wrapper scripts, which manage a personal EC2 instance reached over either an EC2 Instance Connect Endpoint or AWS SSM Session Manager. See the [Developer](developer.md#remote-ssh-cloud-development-environment) documentation.

Unlike every other file in [iam/](iam/), which is attached to a *principal* (a user or role that runs `packer build` or `terraform apply`), [`packer-instance-profile.json`](iam/packer-instance-profile.json) is attached to the **Packer build instance's own role**, and is consumed through the instance profile named by the Packer `IAM_INSTANCE_PROFILE` variable. See [Packer build instance profile](#packer-build-instance-profile). The same applies to [`remote-ssh-instance-profile.json`](iam/remote-ssh-instance-profile.json), which is attached to the Remote-SSH development instance's own role and referenced by the `KNFSD_REMOTE_SSH_IAM_PROFILE_NAME` environment variable.

> INFO: These IAM policies do not cover any additional IAM requirements for the KNFSD File Cache [`examples/`](../examples/).

## Files at a glance

| File                               | Status                | Description                                                                                                                                                                              |
| ---------------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packer.json`                      | AMI build             | Standalone IAM policy for `packer build` in [`image/`](../image/).                                                                                                                       |
| `packer-instance-profile.json`     | AMI build (instance)  | Standalone IAM policy for the Packer **build instance** role; required when `SSH_INTERFACE = "session_manager"` or `TAG_BUILD_STATUS = true`.                                            |
| `tf-required.json`                 | Deploy (required)     | Always-required Sids for `terraform apply` in [`deployment/`](../deployment/).                                                                                                           |
| `tf-optional.json`                 | Deploy (deps)         | Feature-gated Sids; attach only when `var.FSID_DATABASE_DEPLOY = true`, `var.ENABLE_NETAPP_AUTO_DETECT = true` (with `var.NETAPP_SECRET != ""`), or `var.TRAFFIC_MODE = "loadbalancer"`. |
| `vpc-endpoints.json`               | Deploy (optional)     | Standalone IAM policy for the [`deployment/vpc-endpoints/`](../deployment/vpc-endpoints/) module.                                                                                        |
| `testing.json`                     | Testing               | Standalone IAM policy for the test-harness; grants SSH-over-SSM + EC2 Instance Connect to reach instances in [`image/smoke-tests/`](../image/smoke-tests/).                              |
| `remote-ssh.json`                  | Remote-SSH            | Standalone IAM policy for the developer running `.devcontainer/dev/remote.sh` or `run-fio-nfs.sh`; covers both the EICE and AWS SSM Session Manager tunnels.                             |
| `remote-ssh-instance-profile.json` | Remote-SSH (instance) | Standalone IAM policy for the Remote-SSH **development instance** role, named by `KNFSD_REMOTE_SSH_IAM_PROFILE_NAME`.                                                                    |

## How to attach

* **AMI-build-only principal** - attach `iam/packer.json`.
* **Packer build instance** - attach `iam/packer-instance-profile.json` to the build instance role (not to the principal running `packer build`), then pass the enclosing instance profile's name via the Packer `IAM_INSTANCE_PROFILE` variable. Required when `SSH_INTERFACE = "session_manager"` or `TAG_BUILD_STATUS = true`. See [Packer build instance profile](#packer-build-instance-profile).
* **Deploy-only principal** - attach `iam/tf-required.json` (required) and `iam/tf-optional.json` (only when at least one gating TF variable is in use).
* **Single combined principal that does both phases** - attach `iam/packer.json`, `iam/tf-required.json`, and `iam/tf-optional.json`.
* **VPC endpoints** - attach `iam/vpc-endpoints.json` to the identity that runs the standalone `deployment/vpc-endpoints/` module. It is self-contained, so it needs no other `iam/` file.
* **Test-harness** - attach `iam/testing.json` to the identity that runs `image/smoke-tests/`.
* **Remote-SSH developer** - attach `iam/remote-ssh.json` to the identity that runs `.devcontainer/dev/remote.sh` or `.devcontainer/dev/run-fio-nfs.sh`. It is self-contained, so it needs no other `iam/` file.
* **Remote-SSH development instance** - attach `iam/remote-ssh-instance-profile.json` to the development instance role (not to the developer's own identity), then pass the enclosing instance profile's name via the `KNFSD_REMOTE_SSH_IAM_PROFILE_NAME` environment variable.

## Required vs Optional Sids

`Status` values:

* **AMI build** - required by `packer build`.
* **AMI build (SSM)** - required only when the Packer `SSH_INTERFACE = "session_manager"`; not needed for the default SSH connection.
* **AMI build (instance)** - attached to the *build instance* role rather than to the principal running `packer build`; required when `SSH_INTERFACE = "session_manager"` or `TAG_BUILD_STATUS = true`.
* **Deploy (required)** - required by every `terraform apply` regardless of feature flags.
* **Deploy (deps)** - required only when the gating Terraform variable is set.
* **Deploy (optional)** - required only when deploying the standalone `deployment/vpc-endpoints/` module.
* **Testing** - required only to run this repository's own test harnesses; not used to build or deploy KNFSD.
* **Remote-SSH** - required only by the optional developer cloud development environment; not used to build or deploy KNFSD.
* **Remote-SSH (instance)** - attached to the *development instance* role rather than to the developer's own identity.

| Sid                                     | File                               | Status                | Notes                                                                                                                                      |
| --------------------------------------- | ---------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `KnfsdPackerBuild`                      | `packer.json`                      | AMI build             | EC2 + Spot fleet + describe actions.                                                                                                       |
| `KnfsdPackerIamPassRole`                | `packer.json`                      | AMI build             | Passes the Packer instance profile to EC2 (scoped via `iam:PassedToService`).                                                              |
| `KnfsdPackerServiceLinkedRoles`         | `packer.json`                      | AMI build             | Creates the Spot service-linked role on first use (scoped via `iam:AWSServiceName`).                                                       |
| `KnfsdSsmPublicParameters`              | `packer.json`                      | AMI build             | Ubuntu base AMI lookup via `amazon-parameterstore`.                                                                                        |
| `KnfsdPackerSsmChannels`                | `packer.json`                      | AMI build (SSM)       | The `ssmmessages:*Channel` actions used to open the Session Manager tunnel; none support resource-level scoping, so `*`.                   |
| `KnfsdPackerSsmStartSession`            | `packer.json`                      | AMI build (SSM)       | Opens the port-forwarding tunnel to port 22; scoped to EC2 instances and the `AWS-StartPortForwardingSession` document.                    |
| `KnfsdPackerSsmManageSession`           | `packer.json`                      | AMI build (SSM)       | `ssm:TerminateSession` to close the tunnel; scoped to SSM session resources.                                                               |
| `KnfsdPackerInstanceSsm`                | `packer-instance-profile.json`     | AMI build (instance)  | Lets the build instance's SSM agent register and serve sessions, and poll the message service; the Session Manager and `ec2messages`.      |
| `KnfsdPackerInstanceTags`               | `packer-instance-profile.json`     | AMI build (instance)  | `ec2:CreateTags` for `TAG_BUILD_STATUS = true`; scoped to EC2 instances.                                                                   |
| `KnfsdKms`                              | `packer.json`,`tf-required.json`   | Deploy (required)     | Encrypted EBS / AMI; cross-account KMS via `kms:CreateGrant` and `kms:DescribeKey`. Required for both phases.                              |
| `KnfsdCompute`                          | `tf-required.json`                 | Deploy (required)     | EC2 launch template, capacity reservation, KNFSD proxy security group, networking lookups, ASG instance polling for `ENABLE_STATUS_CHECK`. |
| `KnfsdAutoScaling`                      | `tf-required.json`                 | Deploy (required)     | KNFSD Auto Scaling Group, scaling policies, lifecycle hooks.                                                                               |
| `KnfsdSsmParameters`                    | `tf-required.json`                 | Deploy (required)     | KNFSD configuration in SSM Parameter Store under `/knfsd/*`.                                                                               |
| `KnfsdCloudWatch`                       | `tf-required.json`                 | Deploy (required)     | CloudWatch alarms and dashboards.                                                                                                          |
| `KnfsdCloudFormation`                   | `tf-required.json`                 | Deploy (required)     | `knfsd-metrics-dashboard` CloudFormation stack.                                                                                            |
| `KnfsdRoute53`                          | `tf-required.json`                 | Deploy (required)     | Required when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`.                                                                       |
| `KnfsdCloudWatchLogs`                   | `tf-required.json`                 | Deploy (required)     | KNFSD log groups.                                                                                                                          |
| `KnfsdIamRoles`                         | `tf-required.json`                 | Deploy (required)     | KNFSD instance role + Lambda execution roles (including attach/detach managed policies).                                                   |
| `KnfsdIamPolicies`                      | `tf-required.json`                 | Deploy (required)     | KNFSD instance policies (EC2 tags, SSM access, etc).                                                                                       |
| `KnfsdIamInstanceProfile`               | `tf-required.json`                 | Deploy (required)     | KNFSD instance profile.                                                                                                                    |
| `KnfsdIamPassRole`                      | `tf-required.json`                 | Deploy (required)     | Passes the KNFSD role to EC2, Lambda, and Auto Scaling.                                                                                    |
| `KnfsdIamReadManagedPolicies`           | `tf-required.json`                 | Deploy (required)     | Reads AWS-managed policies attached to the KNFSD role.                                                                                     |
| `KnfsdAsgSlrCheck`                      | `tf-required.json`                 | Deploy (required)     | Verify the EC2 Auto Scaling service-linked role exists before the ASG is created.                                                          |
| `KnfsdLambda`                           | `tf-required.json`                 | Deploy (deps)         | Required when `TRAFFIC_MODE = "dns_round_robin"` (default; `static_ip` Lambda for secondary ENIs).                                         |
| `KnfsdEventBridge`                      | `tf-required.json`                 | Deploy (deps)         | Required when `TRAFFIC_MODE = "dns_round_robin"` (default); Auto Scaling lifecycle event rules.                                            |
| `KnfsdDynamoDB`                         | `tf-optional.json`                 | Deploy (deps)         | Required when `FSID_MODE = "external"` and `FSID_DATABASE_DEPLOY = true`; provisions the DynamoDB FSID table via control-plane only.       |
| `KnfsdSecretsManager`                   | `tf-optional.json`                 | Deploy (deps)         | Required when `ENABLE_NETAPP_AUTO_DETECT = true` with `NETAPP_SECRET != ""` (NetApp ONTAP credentials).                                    |
| `KnfsdElbSlrCheck`                      | `tf-optional.json`                 | Deploy (deps)         | Required when `TRAFFIC_MODE = "loadbalancer"`; Verify the Elastic Load Balancing service-linked role exists before the NLB is created.     |
| `KnfsdLoadBalancer`                     | `tf-optional.json`                 | Deploy (deps)         | Required when `TRAFFIC_MODE = "loadbalancer"`; manages the Network Load Balancer, target groups, and listeners.                            |
| `KnfsdVpcEndpoints`                     | `vpc-endpoints.json`               | Deploy (optional)     | Interface and gateway VPC endpoints and their tags for the standalone `deployment/vpc-endpoints/` module.                                  |
| `KnfsdVpcEndpointsSecurityGroup`        | `vpc-endpoints.json`               | Deploy (optional)     | Security group for the interface VPC endpoints; skipped when `EXISTING_SECURITY_GROUP_ID` is set.                                          |
| `KnfsdVpcEndpointsNetworking`           | `vpc-endpoints.json`               | Deploy (optional)     | Route table, subnet, and VPC lookups used by the module data sources.                                                                      |
| `KnfsdVpcEndpointsCloudFormation`       | `vpc-endpoints.json`               | Deploy (optional)     | The module's `knfsd-metrics-vpc-endpoints` CloudFormation stack.                                                                           |
| `KnfsdTestingSsmChannels`               | `testing.json`                     | Testing               | `ssm:DescribeInstanceInformation` plus the `ssmmessages:*Channel` actions; none support resource-level scoping, so `*`.                    |
| `KnfsdTestingSsmStartSession`           | `testing.json`                     | Testing               | Opens the SSH tunnel; scoped to EC2 instances and the `AWS-StartSSHSession` document.                                                      |
| `KnfsdTestingSsmManageSession`          | `testing.json`                     | Testing               | `ssm:TerminateSession` / `ssm:ResumeSession`; scoped to SSM session resources.                                                             |
| `KnfsdTestingInstanceConnect`           | `testing.json`                     | Testing               | `ec2-instance-connect:SendSSHPublicKey` to push the short-lived ephemeral key; scoped to EC2 instances.                                    |
| `KnfsdTestingDynamoDB`                  | `testing.json`                     | Testing               | `dynamodb:GetItem` / `dynamodb:Scan` so the harness can assert the FSID mappings; scoped to `knfsd-*` tables.                              |
| `KnfsdRemoteSshEc2`                     | `remote-ssh.json`                  | Remote-SSH            | Manages the developer's own EC2 instance (run/start/stop/terminate/modify) plus the networking and AMI lookups.                            |
| `KnfsdRemoteSshEc2Tags`                 | `remote-ssh.json`                  | Remote-SSH            | `ec2:CreateTags` / `ec2:DeleteTags` for the `Name` and `knfsd-file-cache:*` tags; scoped to instances and volumes.                         |
| `KnfsdRemoteSshIamPassRole`             | `remote-ssh.json`                  | Remote-SSH            | Passes the instance profile named by `KNFSD_REMOTE_SSH_IAM_PROFILE_NAME` to EC2 (scoped via `iam:PassedToService`).                        |
| `KnfsdRemoteSshSsmPublicParameters`     | `remote-ssh.json`                  | Remote-SSH            | Ubuntu base AMI lookup via the public AWS SSM parameters.                                                                                  |
| `KnfsdRemoteSshSsmChannels`             | `remote-ssh.json`                  | Remote-SSH            | `ssm:DescribeInstanceInformation` plus the `ssmmessages:*Channel` actions; none support resource-level scoping, so `*`.                    |
| `KnfsdRemoteSshSsmStartSession`         | `remote-ssh.json`                  | Remote-SSH            | Opens the SSH tunnel for the `ssm` tunnel; scoped to EC2 instances and the `AWS-StartSSHSession` document.                                 |
| `KnfsdRemoteSshSsmManageSession`        | `remote-ssh.json`                  | Remote-SSH            | `ssm:TerminateSession` / `ssm:ResumeSession`; scoped to SSM session resources.                                                             |
| `KnfsdRemoteSshInstanceConnect`         | `remote-ssh.json`                  | Remote-SSH            | `ec2-instance-connect:OpenTunnel` for the `eice` tunnel, and `SendSSHPublicKey` for the `run-fio-nfs.sh` ephemeral key.                    |
| `KnfsdRemoteSshInstanceConnectDescribe` | `remote-ssh.json`                  | Remote-SSH            | `ec2:DescribeInstanceConnectEndpoints` so the EICE ID can be inferred from the VPC when not pinned.                                        |
| `KnfsdRemoteSshInstanceSsm`             | `remote-ssh-instance-profile.json` | Remote-SSH (instance) | Lets the development instance's SSM agent register and serve sessions, and poll the `ec2messages` service.                                 |
| `KnfsdRemoteSshInstanceTags`            | `remote-ssh-instance-profile.json` | Remote-SSH (instance) | `ec2:CreateTags` so the user-data script can self-report `knfsd-file-cache:status`; scoped to EC2 instances.                               |

## Packer connection method

[`packer.json`](iam/packer.json) covers **both** Packer connection methods, so a single attachment works whichever you choose. If you standardize on one method, you can drop the Sids and actions the other method needs:

| Method used                                           | Safe to drop from `packer.json`                                                                                                                                                                 |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SSH only (default, `SSH_INTERFACE = ""`)              | The three `KnfsdPackerSessionManager*` Sids.                                                                                                                                                    |
| Session Manager (`SSH_INTERFACE = "session_manager"`) | `ec2:AuthorizeSecurityGroupIngress` from `KnfsdPackerBuild`. Packer creates a temporary security group but never authorizes an ingress rule, because all SSH traffic is tunnelled over AWS SSM. |

Additionally, when using Session Manager **and** supplying your own security group via `SECURITY_GROUP_ID` or `SECURITY_GROUP_IDS`, you can also drop `ec2:CreateSecurityGroup` and `ec2:DeleteSecurityGroup`, as no temporary security group is created at all.

`ec2:CreateKeyPair` and `ec2:DeleteKeyPair` are required by **both** methods: Packer creates a temporary key pair regardless of the connection interface, and over Session Manager the resulting key authenticates the SSH session running inside the tunnel.

`ec2:DescribeInstanceStatus` (already in `KnfsdPackerBuild`) is what Packer uses to close SSM tunnels gracefully. Without it the AMI still builds, but Packer logs a `Bad exit status` message when tearing the tunnel down.

## Packer build instance profile

An IAM instance profile must be attached to the Packer build instance when either of the following is true:

* `SSH_INTERFACE = "session_manager"` - Packer fails at start-up without it: `no iam_instance_profile defined; session_manager connectivity requires a valid instance profile with AmazonSSMManagedInstanceCore permissions`.
* `TAG_BUILD_STATUS = true` - the build scripts call `ec2:CreateTags` from the instance itself.

Because a restrictive environment cannot create IAM resources during a build, an administrator pre-creates the role and instance profile once, and the operator then references it by **name** via the Packer `IAM_INSTANCE_PROFILE` variable.

An EC2 role needs two separate documents. [`packer-instance-profile.json`](iam/packer-instance-profile.json) is the **permissions policy** (what the instance may do). The `trust-policy.json` below (what may assume the role) is passed separately to `iam:CreateRole`, and is always exactly `ec2.amazonaws.com` for an instance profile:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Create all three resources as follows, substituting your own names:

```bash
aws iam create-role \
  --role-name knfsd-packer-build \
  --assume-role-policy-document file://trust-policy.json

aws iam put-role-policy \
  --role-name knfsd-packer-build \
  --policy-name knfsd-packer-build \
  --policy-document file://docs/iam/packer-instance-profile.json

aws iam create-instance-profile \
  --instance-profile-name knfsd-packer-build

aws iam add-role-to-instance-profile \
  --instance-profile-name knfsd-packer-build \
  --role-name knfsd-packer-build
```

Then set the instance profile name in your Packer variables file:

```hcl
IAM_INSTANCE_PROFILE = "knfsd-packer-build"
```

## Remote-SSH development instance profile

The optional developer cloud development environment (`.devcontainer/dev/remote.sh`) always requires an IAM instance profile, referenced by **name** via the `KNFSD_REMOTE_SSH_IAM_PROFILE_NAME` environment variable. The attached role needs [`remote-ssh-instance-profile.json`](iam/remote-ssh-instance-profile.json) because:

* The AWS SSM agent must register with Systems Manager for the `ssm` tunnel to connect. Without these permissions `remote.sh` waits for the agent and then times out.
* The user-data script self-reports the `knfsd-file-cache:status` tag via `ec2:CreateTags`, which is how `remote.sh` detects that provisioning has finished.

Create the role and instance profile exactly as for the Packer build instance above, reusing the same `ec2.amazonaws.com` trust policy and substituting the policy document:

```bash
aws iam create-role \
  --role-name knfsd-remote-ssh \
  --assume-role-policy-document file://trust-policy.json

aws iam put-role-policy \
  --role-name knfsd-remote-ssh \
  --policy-name knfsd-remote-ssh \
  --policy-document file://docs/iam/remote-ssh-instance-profile.json

aws iam create-instance-profile \
  --instance-profile-name knfsd-remote-ssh

aws iam add-role-to-instance-profile \
  --instance-profile-name knfsd-remote-ssh \
  --role-name knfsd-remote-ssh
```

Then export the instance profile name before creating the instance:

```bash
export KNFSD_REMOTE_SSH_IAM_PROFILE_NAME=knfsd-remote-ssh
```

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

## Deploying under restrictive IAM (centrally-managed networking and IAM)

Some environments deny the deploying role the ability to create security groups or IAM resources, because networking and IAM are managed centrally and pre-created before application deployments. By default the module self-creates these resources (the canonical policies above grant the required create permissions), and this behaviour is unchanged.

To deploy under a restrictive role, pre-create the resource and set the matching Terraform variable. Each variable lets you *drop* create-permissions rather than add new ones:

| Variable                                                | Pre-create instead                                    | Sids / actions you can then drop                                                                                                                                                         |
| ------------------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EXISTING_SECURITY_GROUP_ID` (root and `vpc-endpoints`) | The security group and its ingress/egress rules       | `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`, `ec2:AuthorizeSecurityGroup*`, `ec2:RevokeSecurityGroup*` (in `KnfsdCompute`, and the equivalent actions in `vpc-endpoints.json`). |
| `EXISTING_INSTANCE_PROFILE_NAME`                        | The IAM role, instance profile, and its policies      | The entire `KnfsdIamRoles`, `KnfsdIamPolicies`, `KnfsdIamInstanceProfile`, and `KnfsdIamPassRole` Sids.                                                                                  |
| `EXISTING_LAMBDA_ROLE_ARN` (`dns_round_robin`)          | The `static_ip` Lambda IAM role and policy            | The Lambda role/policy subset of `KnfsdIamRoles` / `KnfsdIamPolicies` (`iam:CreateRole`/`iam:CreatePolicy` for the Lambda role).                                                         |
| `FSID_DATABASE_IAM_POLICY` (root and `database`)        | The DynamoDB access IAM policy (table still deployed) | `iam:CreatePolicy` (and its versioning actions) for the DynamoDB access policy in `KnfsdIamPolicies`.                                                                                    |

For the AMI build phase, the equivalent is the Packer `IAM_INSTANCE_PROFILE` variable: the build principal never needs to create IAM resources, because the role and instance profile are pre-created by an administrator and referenced by name. The build principal still needs `iam:GetInstanceProfile` and `iam:PassRole` (`KnfsdPackerIamPassRole`) to attach the pre-created profile to the build instance. See [Packer build instance profile](#packer-build-instance-profile).

Notes:

* The embedded runtime policies (DynamoDB access, the `static_ip` Lambda policy, and the instance tag / SSM policies) are still created by Terraform by default. They are only skipped when the matching Terraform variable is set, and the module falls back to the resource you provide.
* The service-linked role pre-flight checks (`KnfsdAsgSlrCheck`, `KnfsdElbSlrCheck`) need only `iam:ListRoles`, which is already granted. If a required service-linked role is missing, the module fails early with a clear message and a remediation command; create it once with, for example, `aws iam create-service-linked-role --aws-service-name autoscaling.amazonaws.com`.

## Naming-prefix recommendation

Several Sids scope their `Resource` ARNs to `knfsd-*` (CloudFormation, Lambda, EventBridge, IAM roles/policies/instance-profiles, Secrets Manager, CloudWatch Logs, DynamoDB tables). This requires deployed resource names to start with `knfsd-`.

The default values aligning with the canonical policies are:

* `var.PROXY_BASENAME` defaults to `knfsd` (from `terraform-module-knfsd/variables.tf`). The module's `local.name` fallback prefixes the random hex with `knfsd-` so the result is always `knfsd-<hex>`.
* `var.NAME_PREFIX` in the database module defaults to `knfsd-fsids`.

If you override these Terraform variables, ensure the override starts with `knfsd-` (or update the `Resource` ARNs in your local copy of the IAM policies to match). In particular, the `KnfsdDynamoDB` Sid only matches FSID tables named `knfsd-*`; when `terraform-module-knfsd` passes the cluster name to the database module, the table is named `<PROXY_BASENAME>-<hex>-fsids`, so the `knfsd` basename prefix convention keeps it in scope.
