# Prerequisites

Before deploying KNFSD to Amazon Web Services, there are a number of prerequisites that you should ensure are met. These are detailed below. Once you have verified the prerequisites, you can continue with the [infrastructure deployment steps](../README.md).

We assume [bash](https://www.gnu.org/software/bash/) and [jq](https://stedolan.github.io/jq/download/) are installed by default on most Linux and macOS systems. Windows machines should be checked.

## Minimum Requirements

- [Git](https://git-scm.com/downloads)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://www.terraform.io/downloads.html)
- [Docker](https://docs.docker.com/get-docker/) (only required to deploy the RDS database module or if running the `.devcontainer` configuration)

### Git

Git is required to clone the [KNFSD-File-Cache](https://github.com/awslabs/knfsd-file-cache) GitHub repository. If you are deploying the DB module from Windows, you should ensure that you have `git-bash` installed (which by default is included with [Git for Windows](https://gitforwindows.org/)).

### AWS CLI

You should ensure that you have [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and credentials configured on your machine.

### Terraform

You should ensure that you have [Terraform](https://www.terraform.io/downloads.html) v1.2.9 or newer installed.

### Docker

Docker engine is required to deploy the Amazon RDS `database` module.

### Docker Desktop (Optional)

> NOTE: Ensure you start Docker Desktop at least once to accept the terms and conditions.

If you wish to use the `.devcontainer/prod` configuration (which is recommended and already contains all required components as well as an optimized environment for KNFSD build and deployment), you should install Docker Desktop (which includes `docker` engine) and the VS Code [Dev Containers Extension](vscode:extension/ms-vscode-remote.remote-containers).

For KNFSD developers, you can use either VS Code or Cursor to run a `.devcontainer/dev` workspace. See [developer.md](../../docs/developer.md) for detailed steps.

> **NOTE**: Cursor now maintains its own Dev Containers Extension. You should use it instead of the VS Code Dev Containers Extension.

## AWS Service Quotas

By default, a new AWS account will have 5 vCPUs (On-Demand) available. This is insufficient for the `c6in.2xlarge` instance type used in the Packer build process, which requires 8 vCPUs or the default `i3en.6xlarge` instance type used as the KNFSD proxy, which requires 24 vCPUs. For each additional KNFSD node, you will need to multiply the number of vCPUs by the maximum number of nodes you plan to deploy. You should also add a 25% buffer to the total number of vCPUs required.

You will need to request a [quota increase](https://console.aws.amazon.com/servicequotas/home) for the total number of On-Demand vCPUs required. Please note that EC2 Spot vCPU service quotas are not applicable to this solution, but will be necessary for your EC2 compute instances.

See [AWS Service Quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html) for more information.

## KNFSD VM Image

Before you can deploy KNFSD in your Amazon Web Services account, you first need to build an AMI (Amazon Machine Image). The process for building this image via Packer is documented [here](../../image/README.md).

## External FSID database

If using the recommended `FSID_MODE="external"`, the knfsd proxy instances will need to be able to access the external FSID database, which by default is deployed into the same subnet as the KNFSD proxy instances. However, it is also possible to deploy the FSID database into a different subnet, or even a different VPC.

By default, `ENABLE_PUBLIC_IP` is set to `false`, so the Amazon RDS PostgreSQL instance will be deployed with a private IP address.

When the DB instance is publicly accessible (`ENABLE_PUBLIC_IP=true`) and you connect from outside of the DB instance's Virtual Private Cloud (VPC), its Domain Name System (DNS) endpoint resolves to the public IP address. When you connect from within the same VPC as the DB instance, the endpoint resolves to the private IP address. Access to the DB instance is ultimately controlled by the EC2 security group it uses. Public access isn't permitted if the security group assigned to the DB instance doesn't permit it. When the DB instance isn't publicly accessible, it is an internal DB instance with a DNS name that resolves to a private IP address.

## Security Groups

The Terraform module(s) will automatically create a Security Group (firewall) for each of the following resources (when necessary):

- Auto Scaling Group
- Network Load Balancer (if `TRAFFIC_MODE = "loadbalancer"`)
- RDS DB instance (if `FSID_MODE = "external"` and `FSID_DATABASE_DEPLOY = true`)
- Lambda function

However, it **will not** create any other security groups. You should make sure that you implement security groups (and any NACLs) to allow:

- KNFSD Node --> Source NFS Server communication (consult your network administrator for guidance on your VPN/DirectConnect to VPC configuration)
- NFS Clients --> KNFSD Node communication (see [security-groups.md](security-groups.md) for guidance on how this is configured)

## Metrics

KNFSD supports a range of metrics which are automatically exported into Amazon CloudWatch.

> NOTE: This step only needs to be ran once per AWS account.

An optional `metrics` Terraform module will automatically create an Amazon CloudWatch custom dashboard, which can be used to easily understand KNFSD performance. Instructions on how to do this are available [here](../metrics/README.md).

## AWS PrivateLink

By default, it is assumed your subnet has internet connectivity to connect to AWS services. Connectivity could be via a NAT gateway and route table to allow access to the internet from your private subnet or via another network construct such as AWS Transit Gateway, which is beyond the scope of this documentation.

AWS [PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html) is a feature that allows you to create a private connection between your VPC and AWS services. This allows you to securely access AWS services without exposing your resources to the public internet.

When deploying KNFSD File Cache in a private subnet without any internet connectivity, VPC endpoints (PrivateLink) are required for AWS service access. See [VPC Endpoints](vpc-endpoints.md) for detailed setup instructions. In this situation, you will need to ensure the VPC endpoints exist **BEFORE** deploying KNFSD modules.

## IAM Permissions

The Terraform module(s) will automatically create an IAM instance profile, role(s) and least-privilege policies for all resources within this solution to operate correctly. Please review the following Terraform files to understand the permissions that are created:

- [terraform-module-knfsd/iam.tf](../terraform-module-knfsd/iam.tf)
- [database/main.tf](../database/main.tf)
- [modules/dns_round_robin/lambda.tf](../terraform-module-knfsd/modules/dns_round_robin/lambda.tf)

## AWS Services

For reference, the following AWS services are used in this solution (and should be available in all new AWS regions as well as AWS GovCloud (US) regions):

- [Amazon EC2](https://aws.amazon.com/ec2/)
- [Amazon Elastic Block Store](https://aws.amazon.com/ebs/)
- [Amazon EC2 Auto Scaling](https://aws.amazon.com/autoscaling/)
- [AWS Systems Manager](https://aws.amazon.com/systems-manager/)
- [Amazon RDS for PostgreSQL](https://aws.amazon.com/rds/postgresql/)
- [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/)
- [Amazon Virtual Private Cloud](https://aws.amazon.com/vpc/)
- [AWS Identity and Access Management](https://aws.amazon.com/iam/)
- [AWS Security Token Service](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html)
- [AWS Lambda](https://aws.amazon.com/lambda/)
- [Amazon Route 53](https://aws.amazon.com/route53/)
- [Amazon EventBridge](https://aws.amazon.com/eventbridge/)
- [AWS Key Management Service](https://aws.amazon.com/kms/)
- [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)

Optional:

- [Amazon Elastic File System](https://aws.amazon.com/efs/) (needed for [examples/efs](../../examples/efs/README.md))
- [FSx for OpenZFS](https://aws.amazon.com/fsx/openzfs/) (needed for [examples/fsx-zfs](../../examples/fsx-zfs/README.md))
- [FSx for NetApp ONTAP](https://aws.amazon.com/fsx/netapp-ontap/) (needed for [examples/fsx-netapp](../../examples/fsx-netapp/README.md))
- [Amazon S3 Files](https://aws.amazon.com/s3/features/files/) (needed for [examples/s3-files](../../examples/s3-files/README.md))
