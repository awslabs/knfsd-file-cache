# KNFSD AMI Build

This directory contains scripts for building an Amazon Web Services [AMI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) for KNFSD.

We start with the base AWS/Canonical Ubuntu 26.04 image, and use the scripts in this directory to build the AWS optimized KNFSD image.

For details of the modifications that are made to the base image, see [resources/scripts](resources/scripts).

## Customizing the image

If you need to add custom steps before the build process, you can provide a path to a bash script file via the `CUSTOM_PRE_BUILD_SCRIPT` variable.

If you need to customize the image post build (e.g. installing custom metric agents), then you can provide a path to a bash script file via the `CUSTOM_POST_BUILD_SCRIPT` variable.

> NOTE: If your custom scripts need to access AWS resources, you must provide an IAM instance profile via the `IAM_INSTANCE_PROFILE` variable. This profile should have the necessary permissions for your scripts to execute successfully.

> NOTE: To have the build instance report its progress via the `knfsd-file-cache:status` tag, set `TAG_BUILD_STATUS = true` and provide an `IAM_INSTANCE_PROFILE` whose role holds the `ec2:CreateTags` permission. See [Build status tagging](#build-status-tagging).

Alternatively, if your build procedure is more complex, you can replace the customization step(s) with your own process.

## Build status tagging

During the build, the provisioning scripts can report their progress by setting the `knfsd-file-cache:status` tag on the build instance. This is disabled by default because it requires the build instance to be able to call the EC2 API.

To enable it:

1. Set `TAG_BUILD_STATUS = true` in your Packer variables file.
2. Set `IAM_INSTANCE_PROFILE` to the name of an IAM instance profile that is attached to the build instance and whose role holds at least the `ec2:CreateTags` permission.

## Build Using Packer

The easiest way to build the AMI is using Packer.

Download Packer 1.16.0 or newer from <https://packer.io/downloads>.

### Clone the KNFSD repository

```bash
git clone https://github.com/awslabs/knfsd-file-cache.git
```

### Create Packer Variables File

Create a new packer variables file (e.g. `image.pkrvars.hcl`).

```bash
cd knfsd-file-cache/image
touch image.pkrvars.hcl
```

Enter at least the following required variable (additional `SUBNET` variable is required only if using a non-default VPC):

#### Required

> NOTE: The AWS region set via `aws configure` or `AWS_DEFAULT_REGION` or `AWS_REGION` environment variable is ignored by Packer.

| Name     | Description                                                                                               | Type   | Required | Default    |
|----------|-----------------------------------------------------------------------------------------------------------|--------|----------|------------|
| `REGION` | The name of the AWS region, such as `"us-east-1"`, in which to launch the EC2 instance to create the AMI. | string | True     | No default |

#### Optional

| Name                                        | Description                                                                                                                                                                                                                                                                            | Type         | Required | Default                                             |
|---------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------|----------|-----------------------------------------------------|
| `SUBNET`                                    | The subnet in which to launch the EC2 instance to create the AMI. This is required if using a non-default VPC. Example: `"subnet-0f90440e0e47728b8"`.                                                                                                                                  | string       | True     | `""`                                                |
| `ASSOCIATE_PUBLIC_IP_ADDRESS`               | If using a non-default VPC, whether to forcefully associate a public IP address with the EC2 instance.                                                                                                                                                                                 | bool         | False    | `null`                                              |
| `SECURITY_GROUP_ID`                         | The ID of an existing, single security group to use instead of creating a temporary one.<br><br>When specified, overrides `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` and `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS`.                                                                     | string       | False    | `""`                                                |
| `SECURITY_GROUP_IDS`                        | A list of security group IDs to use instead of creating a temporary one.<br><br>When specified, overrides `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` and `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS`.                                                                                     | list(string) | False    | `[]`                                                |
| `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS`     | A list of CIDR blocks to allow access from when creating a temporary security group.<br><br>When specified, overrides `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP`. Example: `["10.0.0.0/8", "172.16.0.0/12"]`.                                                                         | list(string) | False    | `[]`                                                |
| `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` | Whether to allow access from the public IP address of the machine running Packer when creating a temp security group.<br><br>Used when `SECURITY_GROUP_ID`, `SECURITY_GROUP_IDS`, and `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` are not specified. \*                                    | bool         | False    | `true`                                              |
| `SSH_INTERFACE`                             | The network interface Packer uses to connect to the build instance. One of `"public_ip"`, `"private_ip"`, `"public_dns"`, `"private_dns"`, `"ipv6"`, or `"session_manager"`.<br><br>Empty uses the Packer default (public IP address if available, otherwise private IP address). \*\* | string       | False    | `""`                                                |
| `SESSION_MANAGER_PORT`                      | The local port on the machine running Packer to use as the local end of the AWS SSM tunnel.<br><br>Only used when `SSH_INTERFACE = "session_manager"`. Zero lets Packer choose an available port between 8000 and 9000.                                                                | number       | False    | `0`                                                 |
| `ARCH`                                      | List of architectures to build. Valid values: `["amd64"]`, `["arm64"]`, or `["amd64", "arm64"]`.                                                                                                                                                                                       | list(string) | False    | `["amd64", "arm64"]`                                |
| `BUILD_NAME`                                | The name applied to all resources during the image build phase. Architecture suffix (`_amd64` or `_arm64`) is automatically appended.                                                                                                                                                  | string       | False    | `"packer-knfsd-proxy-{VERSION}-{ARCH}-{TIMESTAMP}"` |
| `IMAGE_NAME`                                | The unique name of the resulting image. Architecture suffix (`_amd64` or `_arm64`) is automatically appended.                                                                                                                                                                          | string       | False    | `"knfsd-proxy-{VERSION}-{ARCH}"`                    |
| `SKIP_CREATE_IMAGE`                         | Skip creating the image. Useful for setting to `true` during a build test stage.                                                                                                                                                                                                       | bool         | False    | `false`                                             |
| `IAM_INSTANCE_PROFILE`                      | The name of an IAM instance profile to attach to the build instance. Required if your custom scripts need to access AWS resources, or if `TAG_BUILD_STATUS` is `true`.                                                                                                                 | string       | False    | `""`                                                |
| `TAG_BUILD_STATUS`                          | Whether to update the build instance status via the `knfsd-file-cache:status` tag.<br><br>Requires `IAM_INSTANCE_PROFILE` to be set to an instance profile whose role holds the `ec2:CreateTags` permission.                                                                           | bool         | False    | `false`                                             |
| `CUSTOM_PRE_BUILD_SCRIPT`                   | Path to a bash script file to run BEFORE the `10_build.sh` script. For example `"/home/$USER/myscript.sh"`.                                                                                                                                                                            | string       | False    | `""`                                                |
| `CUSTOM_POST_BUILD_SCRIPT`                  | Path to a bash script file to run AFTER the `20_post_build.sh` script. For example `"/home/$USER/myscript.sh"`.                                                                                                                                                                        | string       | False    | `""`                                                |
| `DISTRIBUTION_REGIONS`                      | A list of additional AWS regions to copy the resulting AMI into. The build region is always governed by `REGION`. Example: `["us-east-2", "us-west-2"]`.                                                                                                                               | list(string) | False    | `[]`                                                |
| `AMI_ENCRYPTED`                             | Whether the resulting AMI is encrypted. When `true` the AMI is encrypted with `KMS_KEY_ID` (or the region's default `aws/ebs` key when `KMS_KEY_ID` is empty). \*\*\*                                                                                                                  | bool         | False    | `true`                                              |
| `KMS_KEY_ID`                                | Customer-managed KMS key identifier (key ID, alias, key ARN, or alias ARN) used to encrypt the AMI in the AWS build region.<br><br>Empty uses the AWS region's default `aws/ebs` key when `AMI_ENCRYPTED = true`.                                                                      | string       | False    | `""`                                                |
| `REGION_KMS_KEY_IDS`                        | Map of AWS region to customer-managed KMS key identifier used when distributing the AMI via `DISTRIBUTION_REGIONS`.<br><br>Use when each destination region has a distinct CMK. Empty string in the map means use that AWS region's default `aws/ebs` key. \*\*\*\*                    | map(string)  | False    | `{}`                                                |

\* Ignored when `SSH_INTERFACE = "session_manager"`.

\*\* Set to `"session_manager"` to tunnel SSH over AWS SSM, which requires `IAM_INSTANCE_PROFILE`. See [AWS SSM Session Manager](#aws-ssm-session-manager).

\*\*\* When `false` the AMI is unencrypted. The AWS account-level "EBS encryption by default" setting (when enabled) overrides this to `true`.

\*\*\*\* When this map is empty, `KMS_KEY_ID` is reused for every region in `DISTRIBUTION_REGION` (suitable for multi-region KMS keys or AWS-managed `aws/ebs` defaults).

#### Example: `image.pkrvars.hcl`

```hcl
REGION = "us-east-1"
SUBNET = "subnet-0f90440e0e47728b8"
```

### Authentication

The AWS provider in Packer offers a flexible means of providing credentials for authentication. The following methods are supported, in this order:

* Static credentials
* Environment variables
* Shared credentials file
* EC2 Role

See [Authentication](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#authentication) for more information.

### AWS Credentials

If using static credentials, ensure you run `aws configure` to set the `AWS Access Key ID` and `AWS Secret Access Key`.

> NOTE: The AWS region set via `aws configure` or `AWS_DEFAULT_REGION` or `AWS_REGION` environment variable is ignored by Packer.

```bash
$ aws configure

AWS Access Key ID [************************]:
AWS Secret Access Key [********************]:
Default region name []: us-east-1
Default output format []: json
```

### IAM Permissions

Ensure [AWS credentials](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#authentication) are available to Packer. The minimum IAM permissions for the Packer AMI build (and the rest of the project) are documented at [docs/iam.md](../docs/iam.md). The standalone, Packer-only IAM policy file is at [docs/iam/packer.json](../docs/iam/packer.json) and can be attached directly to the principal that runs `packer build`.

### Service-Linked Role

The build runs on EC2 Spot instances, which require the `AWSServiceRoleForEC2Spot` service-linked role for `spot.amazonaws.com`. The `iam:CreateServiceLinkedRole` permission in [docs/iam/packer.json](../docs/iam/packer.json) allows Packer to create this role automatically on first use. As an alternative, if the role does not yet exist in the AWS account and the build principal is denied `iam:CreateServiceLinkedRole` (for example under a centrally-managed IAM policy), an administrator can pre-create the service-linked role for `spot.amazonaws.com` before running `packer build` as follows:

```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```

### AWS Service Quotas

By default, a new AWS account will have 5 vCPUs (Spot) available. This is insufficient for any of the EC2 Spot instance types used in the build process, which require **64** vCPUs or more.

You will need to request a [quota increase](https://console.aws.amazon.com/servicequotas/home) for the appropriate EC2 [Spot Instance quotas](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-quotas.html).

See [AWS Service Quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html) for more information.

### AMI Encryption and Cross-Region Distribution

The Packer build supports three encryption modes for the resulting AMI in the AWS build region (`REGION`) and an independent option for distributing copies to additional AWS regions (`DISTRIBUTION_REGIONS`). All customer-managed KMS keys, key policies, and cross-account access are the customer's responsibility - this build only consumes KMS key identifiers.

#### Encryption modes (build region)

* **Default `aws/ebs`** - Leave `KMS_KEY_ID = ""` and `AMI_ENCRYPTED = true` (default). The AMI is encrypted with the AWS build region's AWS-managed `aws/ebs` key. The AMI cannot be shared cross-account because the `aws/ebs` key policy is not editable and AWS region bound.
* **Customer-managed key (CMK)** - Set `KMS_KEY_ID` to your CMK's key ID, alias, key ARN, or alias ARN. The CMK and its key policy must be created and managed by you in the build account/region.
* **Unencrypted** - Set `AMI_ENCRYPTED = false` and leave `KMS_KEY_ID = ""`. The AMI is unencrypted in the build region. The AWS account-level [EBS encryption by default](https://docs.aws.amazon.com/ebs/latest/userguide/work-with-ebs-encr.html#encryption-by-default) setting (when enabled) overrides this back to encrypted.

#### Cross-region distribution (optional)

Set `DISTRIBUTION_REGIONS` to a list of additional AWS regions to copy the KNFSD AMI into. The AWS build region is always governed by `REGION` - do not add it to `DISTRIBUTION_REGIONS`. Three sub-cases:

* **Single multi-region CMK** - Leave `REGION_KMS_KEY_IDS = {}` and use the same identifier in `KMS_KEY_ID` for the build region. The map is auto-populated to reuse `KMS_KEY_ID` for every destination region. Suitable for [AWS KMS multi-Region keys](https://docs.aws.amazon.com/kms/latest/developerguide/multi-region-keys-overview.html) where the same identifier resolves in every region.
* **Per-region CMKs** - Populate `REGION_KMS_KEY_IDS` with an entry per destination region pointing at the region-local CMK. Each region needs a separate key because KMS keys are regional.
* **Default `aws/ebs` per region** - Leave `KMS_KEY_ID = ""` and `REGION_KMS_KEY_IDS = {}`. Packer copies the AMI to each region encrypted under that AWS region's own `aws/ebs` key.

For full upstream semantics see the [Packer `amazon-ebs` AMI configuration](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs#ami-configuration) docs.

#### Cross-account use by an Auto Scaling Group

When the consuming AWS account launches the KNFSD AMI via an Auto Scaling Group with a CMK-encrypted AMI (or sets `EBS_KMS_KEY_ID` in the deployment module), the customer must update the CMK key policy to grant the `AWSServiceRoleForAutoScaling` service-linked role the necessary actions. See [AWS docs - Required AWS KMS key policy for use with encrypted volumes](https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html).

### SSH Connectivity

> NOTE: Ensure the machine you are running Packer on has network connectivity to the AWS subnet you are building the image in and the EC2 instance you are building the image on is accessible over TCP port 22 for SSH access.

> NOTE: If you are expecting your build machine to receive a public IPv4 address, please review this AWS [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/how-it-works.html) and [Public Subnet](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-public-ip.html) documentation for more information.

It is beyond the scope of this documentation to describe all possible SSH setups that can work here and are compliant to your security policies. For further reading, please consult the AWS docs on how you can [connect to your Linux instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html).

The Packer configuration (by default) provides an opinionated setup via a Packer created temporary EC2 Security Group with SSH access from the public internet (`var.TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP = true`), allowlisted to your current public IP /32 address (obtained via [https://checkip.amazonaws.com](https://checkip.amazonaws.com)). If using a non-default VPC, you can set `var.ASSOCIATE_PUBLIC_IP_ADDRESS = true` in the `image.pkrvars.hcl` file to forcefully associate a public IP address with the EC2 instance.

For a stronger security posture or if you work in a corporate network with egress traffic passing via a NAT layer, with multiple possible public IP addresses, you can set `var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` to a list of your CIDR ranges in the `image.pkrvars.hcl` file.

Several other security group variables are available to configure the Packer build process. See the [variables.pkr.hcl](variables.pkr.hcl) file for more information or the [Security Group Usage Scenarios](#security-group-usage-scenarios) section below for examples.

Alternatively, you can provision an EC2 instance within your VPC in your AWS account, `git clone` the project repository, and run the Packer build script. This bypasses the need to run anything from on-premises.

### AWS SSM Session Manager

Instead of connecting over inbound SSH, Packer can tunnel its SSH session through [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html). This allows the AMI to be built in a private subnet with **no inbound SSH, no public IP address, and no bastion host**, which suits locked-down landing zones and aligns the build with the keyless, IAM-authenticated posture the deployed KNFSD proxy already uses.

To enable it, set both of the following in your `image.pkrvars.hcl` file:

```hcl
REGION               = "us-east-1"
SUBNET               = "subnet-0f90440e0e47728b8"
SSH_INTERFACE        = "session_manager"
IAM_INSTANCE_PROFILE = "knfsd-packer-build"
```

`IAM_INSTANCE_PROFILE` is **mandatory** for this mode. Packer fails immediately without it:

```text
no iam_instance_profile defined; session_manager connectivity requires a valid
instance profile with AmazonSSMManagedInstanceCore permissions.
```

The instance profile must be pre-created by an administrator. The minimum permissions policy is [docs/iam/packer-instance-profile.json](../docs/iam/packer-instance-profile.json), and the trust policy plus the `aws iam` commands to create all three resources are documented at [Packer build instance profile](../docs/iam.md#packer-build-instance-profile).

#### Requirements

* **`session-manager-plugin`** must be installed on the machine running Packer and be on its `PATH`, as Packer invokes it as a subprocess to open the tunnel. See [Installing the Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html). It is preinstalled in both the `.devcontainer/dev` and `.devcontainer/prod` configurations.
* **AWS SSM reachability** from the build subnet. If the subnet has no route to the internet, the `ssm`, `ssmmessages`, and `ec2messages` interface VPC endpoints are required; all three are provided by the [vpc-endpoints](../deployment/vpc-endpoints/README.md) module.

#### Egress is still required

> IMPORTANT: Session Manager removes the **inbound** connectivity requirement only. The build itself still downloads packages and sources from the internet, including `cdn.kernel.org` (Linux kernel and `nfs-utils`), `github.com`, `dl.google.com` (Go), `proxy.golang.org`, `launchpad.net`, `amazoncloudwatch-agent.s3.amazonaws.com`, the Ubuntu package archive, and the snap store.

The build subnet therefore still needs egress via a NAT gateway, a proxy, or an equivalent path. A subnet with no egress at all cannot complete the build, regardless of the connection method. Note that `checkip.amazonaws.com` is **not** contacted in this mode, as no temporary security group ingress rule is created.

#### Behaviour notes

* A temporary security group is still created (unless you supply `SECURITY_GROUP_ID` or `SECURITY_GROUP_IDS`), but **no ingress rule is ever authorized**, as all SSH traffic arrives through the SSM tunnel. Supply your own security group only if your environment mandates a specific egress policy.
* A temporary EC2 key pair is still created and used to authenticate the SSH session running inside the tunnel.

#### Expected SSM messages

A successful `session_manager` build logs the following error messages. They are **cosmetic** and do not affect the resulting AMI:

```text
==> amazon-ebs.knfsd-<arm/amd>64: SessionId: <id> : document process failed unexpectedly: ipc messaging received timeout signal , check [ssm-document-worker]/[ssm-session-worker] log for crash reason
==> amazon-ebs.knfsd-<arm/amd>64: Error terminating SSM Session "<id>", this does not affect the built AMI. Please terminate the session manually: ... ValidationException: Session is not in a valid state
```

These messages are caused by the build instance restarting. The AWS SSM agent currently does not survive a restart. It tears down the port forwarding session, the `session-manager-plugin` reports the loss, and Packer's follow-up `ssm:TerminateSession` call is rejected because the session is already terminating. Packer then opens a replacement session and continues.

### Security Group Usage Scenarios

The following scenarios demonstrate different networking and security configurations for building the AMI via Packer.

The precedence order (highest to lowest) is:

1. `SECURITY_GROUP_ID` - overrides all other security settings
2. `SECURITY_GROUP_IDS` - overrides temporary security group settings
3. `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` - overrides public IP source setting
4. `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` - default fallback behavior

The `ASSOCIATE_PUBLIC_IP_ADDRESS` setting is independent of the security group configuration and controls whether the EC2 instance gets a public IP address assigned when using a non-default VPC.

When `SSH_INTERFACE = "session_manager"`, the temporary security group is still created but no ingress rule is authorized, and `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` is ignored. See [AWS SSM Session Manager](#aws-ssm-session-manager).

#### 1. Default VPC with Public IP (Default Behaviour)

```bash
# No variables need to be set - uses all defaults:
# ASSOCIATE_PUBLIC_IP_ADDRESS = null
# SECURITY_GROUP_ID = ""
# SECURITY_GROUP_IDS = []
# TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS = []
# TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP = true
```

#### 2. Non-Default VPC with Public IP Association

```bash
# Only need to force public IP association in non-default VPC:
ASSOCIATE_PUBLIC_IP_ADDRESS = true
# All other variables remain at defaults
```

#### 3. Private Subnet with Custom CIDR Access

```bash
# For private subnets, specify internal CIDR ranges:
ASSOCIATE_PUBLIC_IP_ADDRESS = false
TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS = ["10.0.0.0/8", "172.16.0.0/12"]
# SECURITY_GROUP_ID = "" (default)
# SECURITY_GROUP_IDS = [] (default)
# TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP = true (default, but overridden by CIDRS)
```

#### 4. Existing Security Group

```bash
# Use pre-configured security group:
SECURITY_GROUP_ID = "sg-existing123"
# All other variables remain at defaults (will be overridden by SECURITY_GROUP_ID)
```

#### 5. Multiple Existing Security Groups

```bash
# Use multiple security groups:
SECURITY_GROUP_IDS = ["sg-web123", "sg-ssh456"]
# All other variables remain at defaults (will be overridden by SECURITY_GROUP_IDS)
```

#### 6. Disable Public IP Access

```bash
# More restrictive - no public IP source access:
TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP = false
TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS = ["192.168.1.0/24"]
# ASSOCIATE_PUBLIC_IP_ADDRESS = null (default)
# SECURITY_GROUP_ID = "" (default)
# SECURITY_GROUP_IDS = [] (default)
```

#### 7. Private Subnet with No Inbound Access (AWS SSM Session Manager)

```bash
# No inbound SSH, no public IP, no bastion. Requires a pre-created
# instance profile. See the "AWS SSM Session Manager" section above.
SSH_INTERFACE        = "session_manager"
IAM_INSTANCE_PROFILE = "knfsd-packer-build"
# A temporary security group is still created, but no ingress rule is added.
# TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP is ignored in this mode, so
# "https://checkip.amazonaws.com" is never contacted.
# ASSOCIATE_PUBLIC_IP_ADDRESS = null (default)
# SECURITY_GROUP_ID = "" (default)
# SECURITY_GROUP_IDS = [] (default)
```

### Run Packer Build

```bash
cd knfsd-file-cache
packer init -upgrade image/knfsd.pkr.hcl
packer build -var-file image/image.pkrvars.hcl image
```

### Successful Build Output

```bash
amazon-ebs.knfsd: ---- SYSTEM INFO
amazon-ebs.knfsd: Description:  Ubuntu 26.04 LTS
amazon-ebs.knfsd: Release:      26.04
amazon-ebs.knfsd: Codename:     resolute
amazon-ebs.knfsd: Kernel:       7.2.3-knfsd
...
amazon-ebs.knfsd: ---- SUCCESS: Finished finalize image script
...
==> Wait completed after 29 minutes 36 seconds
...
==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs.knfsd: AMIs were created:
us-east-1: ami-0123456789abcdef0
```

Once you have built and verified the AMI for KNFSD, you can deploy the supporting infrastructure by following the steps in the [deployment documentation](../deployment/README.md).

## Additional Information

### Building in AWS GovCloud / China partitions

The KNFSD proxy AMI can be built in AWS Commercial, GovCloud (`aws-us-gov`), and China (`aws-cn`) partitions. The base Canonical Ubuntu 26.04 image is resolved from the public `/aws/service/canonical/...` SSM parameters, which are published in all three partitions, so the Packer AMI lookup works without modification.

The image build process does, however, download several packages from commercial AWS endpoints during provisioning (for example `awscli.amazonaws.com` and `amazoncloudwatch-agent.s3.amazonaws.com` in [resources/scripts/10_build.sh](resources/scripts/10_build.sh)). When building in China:

* Run the build from a China-based pipeline (EC2 build host in a `cn-*` region) that has network egress to the appropriate China mirrors, or pre-stage the packages.
* `checkip.amazonaws.com` (used only as a developer convenience to discover the build host's public IP) is a commercial-only endpoint and is not required for the build itself.

### Run Smoke Tests

You can use the [smoke test suite](smoke-tests/README.md) to verify the basic functionality of the AMI.

### Packer Debugging

If you need to [debug](https://developer.hashicorp.com/packer/docs/debugging) the Packer build process, you can enable debugging by setting the following environment variables and adding the `-debug` flag to the `packer build` command:

```bash
export PACKER_LOG=1
export PACKER_LOG_PATH=packer.log
packer build -debug -var-file image/image.pkrvars.hcl image
```

The `-debug` flag disables Packer parallelization, allows you to step through the build process manually, and emits a verbose log to the current directory as `packer.log`.

Once the EC2 build instance is instantiated, Packer will emit to the current directory an ephemeral private SSH key as a `.pem` file.

Using that you can `ssh -i <key>.pem ubuntu@<instance-ip>` to connect to the instance and see what is going on for debugging. The ephemeral key will be deleted at the end of the Packer run during cleanup.

## Build Manually

Alternatively, you can build the AMI manually via AWS CLI. It is assumed the following prerequisites are met:

* Create/access your AWS account.
* Choose the AWS region where you want to build the AMI.
* Create/import a [key pair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html). We assume a 2048-bit SSH-2 RSA key is used.
* Create VPC or use default VPC, add public subnet, add IGW, add routing table with subnet association to the IGW.
* IAM user with permissions to execute AWS commands listed below.

### Install AWS CLI

Download/install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) and configure with your AWS [credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html).

### Navigate to Image Directory

```bash
cd knfsd-file-cache/image
```

### Update values in the brackets `<...>` below and set the shell variables

```bash
VERSION="1.1.0-beta.3"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)

export KNFSD_REGION=<region-name>
export KNFSD_SUBNET=<subnet-id>
export KNFSD_KEYPAIR=<keypair-name>
export KNFSD_ARCH=<amd64-or-arm64>  # Choose: amd64 or arm64

export KNFSD_BUILD_NAME="build-knfsd-proxy-${VERSION}-${KNFSD_ARCH}-${TIMESTAMP}"
export KNFSD_AMI_NAME="knfsd-proxy-${VERSION}-${KNFSD_ARCH}-${TIMESTAMP}"
export KNFSD_IMAGE_NAME="knfsd-proxy-${VERSION}-${KNFSD_ARCH}"
```

### (Optional) Create Security Group for SSH Access

It is beyond the scope of this documentation to describe all possible SSH setups that can work here and are compliant to your security policies. For further reading, please consult the AWS public docs on how you can [connect to your Linux instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html). One option is to provision an [Amazon EC2 Instance Connect (EIC) Endpoint](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html) (free), which is explained further in the KNFSD [Developer](../docs/developer.md#remote-ssh-ec2-instance-connect-eic-endpoint) documentation.

For simplicity, this documentation provides an opinionated setup via an EC2 Security Group with SSH access from the public internet, allowlisted to your current IP address.

```bash
vpc_id=$(aws ec2 describe-subnets --subnet-ids $KNFSD_SUBNET --query 'Subnets[0].VpcId' --output text)
export KNFSD_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name $KNFSD_BUILD_NAME \
  --vpc-id $vpc_id \
  --description "SSH access to KNFSD build machine" \
  --region $KNFSD_REGION \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${KNFSD_BUILD_NAME}},{Key=knfsd-file-cache:version,Value=${VERSION}}]" \
  --output text \
  --query 'GroupId')

my_ip=$(curl -s https://checkip.amazonaws.com)/32
aws ec2 authorize-security-group-ingress \
  --group-id $KNFSD_SECURITY_GROUP_ID \
  --protocol tcp \
  --port 22 \
  --cidr $my_ip \
  --region $KNFSD_REGION
```

### Create Build Machine

The instance type used depends on your architecture choice:

* `c6i.16xlarge` for amd64 builds, 64 vCPUs (EC2 On-Demand)
* `c7g.16xlarge` for arm64 builds, 64 vCPUs (EC2 On-Demand)

**Note**: You will need to provide an `$KNFSD_SECURITY_GROUP_ID` to create the build machine.

```bash
# set instance type based on architecture
if [ "$KNFSD_ARCH" = "amd64" ]; then
  KNFSD_INSTANCE_TYPE="c6i.16xlarge"
elif [ "$KNFSD_ARCH" = "arm64" ]; then
  KNFSD_INSTANCE_TYPE="c7g.16xlarge"
fi

export KNFSD_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/canonical/ubuntu/server/26.04/stable/current/${KNFSD_ARCH}/hvm/ebs-gp3/ami-id \
  --instance-type $KNFSD_INSTANCE_TYPE \
  --key-name $KNFSD_KEYPAIR \
  --subnet-id $KNFSD_SUBNET \
  --region $KNFSD_REGION \
  --associate-public-ip-address \
  --security-group-ids $KNFSD_SECURITY_GROUP_ID \
  --block-device-mappings '[
    {"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":10,"VolumeType":"gp3","Encrypted":true,"DeleteOnTermination":true}},
    {"DeviceName":"/dev/sdb","NoDevice":""},
    {"DeviceName":"/dev/sdc","NoDevice":""},
    {"DeviceName":"/dev/sdf","Ebs":{"VolumeSize":20,"VolumeType":"gp3","Encrypted":true,"DeleteOnTermination":true}}
    ]' \
  --metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=2,InstanceMetadataTags=enabled" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${KNFSD_BUILD_NAME}},{Key=knfsd-file-cache:version,Value=${VERSION}}]" \
  --user-data file://build-user-data.sh \
  --query 'Instances[0].InstanceId' \
  --output text)

# short sleep to allow instance IP to be assigned
sleep 5

export KNFSD_INSTANCE_PUBLIC_IP=$(aws ec2 describe-instances --region $KNFSD_REGION --instance-ids $KNFSD_INSTANCE_ID --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
```

### Copy Resources to Build Machine

Wait for the instance to be `Running` and `3/3 checks passed` in AWS Console.

```bash
tar -czf resources.tgz -C resources .
scp -i /path/to/$KNFSD_KEYPAIR resources.tgz ubuntu@$KNFSD_INSTANCE_PUBLIC_IP:/mnt/build
```

### SSH to Build Machine

```bash
ssh -i /path/to/$KNFSD_KEYPAIR ubuntu@$KNFSD_INSTANCE_PUBLIC_IP
```

### Run the Build Image Script

```bash
cd /mnt/build
tar -zxf resources.tgz
chmod +x scripts/*.sh
# execute build script
sudo bash scripts/10_build.sh 2>&1
```

When the `10_build.sh` script completes you should see:

```text
---- SUCCESS: Finished build image script. Reboot(ing) for new kernel to take effect
```

### Reboot Build Machine

Check there were no errors and reboot the machine. This will restart the build machine with the new kernel.

```bash
sudo reboot
```

**NOTE: When your build machine reboots, your ssh session will revert to your host machine.**

### SSH to Build Machine to run subsequent commands

```bash
ssh -i /path/to/$KNFSD_KEYPAIR ubuntu@$KNFSD_INSTANCE_PUBLIC_IP
# re-mount the build disk
device=$(lsblk -o NAME,SIZE,TYPE | grep 'disk' | grep '20G' | awk '{print $1}' | head -n1)
sudo mount "/dev/$device" /mnt/build
cd /mnt/build
# execute post build script
sudo bash scripts/20_post_build.sh 2>&1
```

### Customize the Image

If you have custom build steps, run them now.

### Finalize the Image

This will clean up the local disk prior to creating the image.

Once the clean up is complete, the instance will shutdown.

```bash
# execute finalize script
sudo bash scripts/30_finalize.sh 2>&1
cd ~
sudo umount /mnt/build
sudo rm -rf /mnt/build
sudo shutdown -h now
```

### Successful Build

A successful build will output something similar to the following:

```bash
---- SYSTEM INFO
Description:  Ubuntu 26.04 LTS
Release:      26.04
Codename:     resolute
Kernel:       7.2.3-knfsd
---- SUCCESS: Finished finalize image script
```

### Create the custom AMI

Once the instance is shutdown, you can create the custom AMI.

```bash
ami_id=$(aws ec2 create-image \
  --region $KNFSD_REGION \
  --instance-id $KNFSD_INSTANCE_ID \
  --name $KNFSD_AMI_NAME \
  --description "NFS Caching Proxy Server, v$VERSION, Canonical, Ubuntu, 26.04 LTS, AMD64 Resolute image built on $TIMESTAMP" \
  --block-device-mappings '[
    {"DeviceName":"/dev/sda1","Ebs":{"DeleteOnTermination":true,"Encrypted":true}},
    {"DeviceName":"/dev/sdb","NoDevice":""},
    {"DeviceName":"/dev/sdc","NoDevice":""},
    {"DeviceName":"/dev/sdf","NoDevice":""}
    ]' \
  --tag-specifications \
    "ResourceType=image,Tags=[{Key=Name,Value=${KNFSD_IMAGE_NAME}},{Key=knfsd-file-cache:version,Value=${VERSION}}]" \
    "ResourceType=snapshot,Tags=[{Key=Name,Value=${KNFSD_IMAGE_NAME}},{Key=knfsd-file-cache:version,Value=${VERSION}}]" \
  --query 'ImageId' \
  --output text)
```

Wait for the AMI to be available, then set the IMDS support to v2.0.

```bash
aws ec2 modify-image-attribute \
  --region $KNFSD_REGION \
  --image-id $ami_id \
  --imds-support "v2.0"
```

### Delete Build Resources (via host machine)

```bash
aws ec2 terminate-instances --region $KNFSD_REGION --instance-ids $KNFSD_INSTANCE_ID
# optional
aws ec2 delete-security-group --region $KNFSD_REGION --group-id $KNFSD_SECURITY_GROUP_ID
```

## Deploy KNFSD Infrastructure

Once you have built and verified the AMI for KNFSD, you can deploy the supporting infrastructure by following the steps in the [deployment documentation](../deployment/README.md).
