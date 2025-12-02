# Instructions

This directory contains scripts for building an Amazon Web Services [AMI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) for KNFSD.

We start with the base AWS/Canonical Ubuntu 24.04 image, and use the scripts in this directory to build the AWS optimized KNFSD image.

For details of the modifications that are made to the base image, see [resources/scripts](resources/scripts).

## Customizing the image

If you need to add custom steps before the build process, you can provide a path to a bash script file via the `CUSTOM_PRE_BUILD_SCRIPT` variable.

If you need to customize the image post build (e.g. installing custom metric agents), then you can provide a path to a bash script file via the `CUSTOM_POST_BUILD_SCRIPT` variable.

> NOTE: If your custom scripts need to access AWS resources, you must provide an IAM instance profile via the `IAM_INSTANCE_PROFILE` variable. This profile should have the necessary permissions for your scripts to execute successfully.

Alternatively, if your build procedure is more complex, you can replace the customization step(s) with your own process.

## Build Using Packer

The easiest way to build the AMI is using Packer.

Download Packer 1.14.0 or newer from <https://packer.io/downloads>.

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

Enter at least the following 2 required variables:

#### Required

> NOTE: The AWS region set via `aws configure` or `AWS_DEFAULT_REGION` or `AWS_REGION` environment variable is ignored by Packer.

* `REGION` (string) - The name of the AWS region, such as `"us-east-1"`, in which to launch the EC2 instance to create the AMI. No default.
* `SUBNET` (string) - The subnet in which to launch the EC2 instance to create the AMI. Example: `"subnet-0f90440e0e47728b8"`. No default.

#### Optional

* `ASSOCIATE_PUBLIC_IP_ADDRESS` (bool) - If using a non-default VPC, whether to forcefully associate a public IP address with the EC2 instance. Default: `null`.
* `SECURITY_GROUP_ID` (string) - The ID of an existing, single security group to use instead of creating a temporary one. When specified, overrides `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` and `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS`. Default: `""`.
* `SECURITY_GROUP_IDS` (list(string)) - A list of security group IDs to use instead of creating a temporary one. When specified, overrides `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` and `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS`. Default: `[]`.
* `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` (list(string)) - A list of CIDR blocks to allow access from when creating a temporary security group. When specified, overrides `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP`. Example: `["10.0.0.0/8", "172.16.0.0/12"]`. Default: `[]`.
* `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` (bool) - Whether to allow access from the public IP address of the machine running Packer when creating a temporary security group. Only used when `SECURITY_GROUP_ID`, `SECURITY_GROUP_IDS`, and `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` are not specified. Default: `true`.
* `ARCH` (list(string)) - List of architectures to build. Valid values: `["amd64"]`, `["arm64"]`, or `["amd64", "arm64"]`. Default: `["amd64", "arm64"]` (builds both architectures in parallel).
* `BUILD_NAME` (string) - The name applied to all resources during the image build phase. Architecture suffix (`_amd64` or `_arm64`) is automatically appended. Default: `"packer-knfsd-proxy-{VERSION}-{ARCH}-{TIMESTAMP}"`.
* `IMAGE_NAME` (string) - The unique name of the resulting image. Architecture suffix (`_amd64` or `_arm64`) is automatically appended. Default: `"knfsd-proxy-{VERSION}-{ARCH}"`.
* `SKIP_CREATE_IMAGE` (bool) - Skip creating the image. Useful for setting to `true` during a build test stage. Default: `false`.
* `IAM_INSTANCE_PROFILE` (string) - The name of an IAM instance profile to attach to the build instance. Required if your custom scripts need to access AWS resources. Default: `""`.
* `CUSTOM_PRE_BUILD_SCRIPT` (string) - Path to a bash script file to run BEFORE the `10_build.sh` script. For example `"/home/$USER/myscript.sh"`. Default: `""`.
* `CUSTOM_POST_BUILD_SCRIPT` (string) - Path to a bash script file to run AFTER the `20_post_build.sh` script. For example `"/home/$USER/myscript.sh"`. Default: `""`.

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

Ensure [AWS credentials](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#authentication) are available to Packer. The following IAM policy document provides the minimal permissions necessary for this Packer build to work:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PackerPermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateImage",
        "ec2:CreateKeyPair",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:DeleteKeyPair",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteSnapshot",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcs",
        "ec2:ModifyImageAttribute",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "kms:CreateGrant",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncrypt*",
        "ssm:GetParameter"
      ],
      "Resource": "*"
    }
  ]
}
```

### AWS Service Quotas

By default, a new AWS account will have 5 vCPUs (On-Demand) available. This is insufficient for the instance types used in the build process:

* `c6in.2xlarge` (amd64 builds) requires 8 vCPUs
* `c6gn.2xlarge` (arm64 builds) requires 8 vCPUs

You will need to request a [quota increase](https://console.aws.amazon.com/servicequotas/home) for the appropriate instance types.

See [AWS Service Quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html) for more information.

### SSH Connectivity

> NOTE: Ensure the machine you are running Packer on has network connectivity to the AWS subnet you are building the image in and the EC2 instance you are building the image on is accessible over TCP port 22 for SSH access.

> NOTE: If you are expecting your build machine to receive a public IPv4 address, please review this AWS [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/how-it-works.html) and [Public Subnet](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-public-ip.html) documentation for more information.

It is beyond the scope of this documentation to describe all possible SSH setups that can work here and are compliant to your security policies. For further reading, please consult the AWS docs on how you can [connect to your Linux instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html).

The Packer configuration (by default) provides an opinionated setup via a Packer created temporary EC2 Security Group with SSH access from the public internet (`var.TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP = true`), allowlisted to your current public IP /32 address (obtained via [https://checkip.amazonaws.com](https://checkip.amazonaws.com)). If using a non-default VPC, you can set `var.ASSOCIATE_PUBLIC_IP_ADDRESS = true` in the `image.pkrvars.hcl` file to forcefully associate a public IP address with the EC2 instance.

For a stronger security posture or if you work in a corporate network with egress traffic passing via a NAT layer, with multiple possible public IP addresses, you can set `var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` to a list of your CIDR ranges in the `image.pkrvars.hcl` file.

Several other security group variables are available to configure the Packer build process. See the [variables.pkr.hcl](variables.pkr.hcl) file for more information or the [Security Group Usage Scenarios](#security-group-usage-scenarios) section below for examples.

Alternatively, you can provision an EC2 instance within your VPC in your AWS account, `git clone` the project repository, and run the Packer build script. This bypasses the need to run anything from on-premises.

### Security Group Usage Scenarios

The following scenarios demonstrate different networking and security configurations for building the AMI via Packer.

The precedence order (highest to lowest) is:

1. `SECURITY_GROUP_ID` - overrides all other security settings
2. `SECURITY_GROUP_IDS` - overrides temporary security group settings
3. `TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` - overrides public IP source setting
4. `TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` - default fallback behavior

The `ASSOCIATE_PUBLIC_IP_ADDRESS` setting is independent of the security group configuration and controls whether the EC2 instance gets a public IP address assigned when using a non-default VPC.

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

### Run Packer Build

```bash
cd knfsd-file-cache
packer init -upgrade image/nfs-proxy.pkr.hcl
packer build -var-file image/image.pkrvars.hcl image
```

### Successful Build Output

```bash
amazon-ebs.nfs-proxy: ---- SYSTEM INFO
amazon-ebs.nfs-proxy: Description:  Ubuntu 24.04.3 LTS
amazon-ebs.nfs-proxy: Release:      24.04
amazon-ebs.nfs-proxy: Codename:     noble
amazon-ebs.nfs-proxy: Kernel:       6.14.0-36-generic
...
amazon-ebs.nfs-proxy: ---- SUCCESS: Finished finalize image script
...
==> Wait completed after 19 minutes 36 seconds
...
==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs.nfs-proxy: AMIs were created:
us-east-1: ami-0123456789abcdef0
```

Once you have built and verified the AMI for KNFSD, you can deploy the supporting infrastructure by following the steps in the [deployment documentation](../deployment/README.md).

## Additional Information

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

Using that you can `ssh -i <key>.pem ubuntu@<instance-public-ip>` to connect to the instance and see what is going on for debugging. The ephemeral key will be deleted at the end of the Packer run during cleanup.

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
VERSION="1.1.0-alpha.17"
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

* `c6in.2xlarge` for amd64 builds
* `c6gn.2xlarge` for arm64 builds

**Note**: You will need to provide an `$KNFSD_SECURITY_GROUP_ID` to create the build machine.

```bash
# Set instance type based on architecture
if [ "$KNFSD_ARCH" = "amd64" ]; then
  KNFSD_INSTANCE_TYPE="c6in.2xlarge"
elif [ "$KNFSD_ARCH" = "arm64" ]; then
  KNFSD_INSTANCE_TYPE="c6gn.2xlarge"
fi

export KNFSD_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/${KNFSD_ARCH}/hvm/ebs-gp3/ami-id \
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
Description:  Ubuntu 24.04.3 LTS
Release:      24.04
Codename:     noble
Kernel:       6.14.0-36-generic
---- SUCCESS: Finished finalize image script
```

### Create the custom AMI

Once the instance is shutdown, you can create the custom AMI.

```bash
ami_id=$(aws ec2 create-image \
  --region $KNFSD_REGION \
  --instance-id $KNFSD_INSTANCE_ID \
  --name $KNFSD_AMI_NAME \
  --description "NFS Caching Proxy Server, v$VERSION, Canonical, Ubuntu, 24.04 LTS, AMD64 Noble image built on $TIMESTAMP" \
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
