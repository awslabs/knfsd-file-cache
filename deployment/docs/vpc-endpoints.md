# VPC Endpoints (AWS PrivateLink)

To **operate** KNFSD File Cache in a private subnet without internet connectivity (no IGW or NAT Gateway), the running KNFSD EC2 instances need access to a small set of AWS service APIs. This document provides guidance on setting up the AWS [PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html) (VPC) endpoints required at runtime.

> INFO: This document covers only the runtime path of KNFSD itself. The Terraform host that performs `terraform apply` is assumed to run from a network with public AWS reachability and is therefore out of scope. The endpoints listed here do not cover the additional deployment-time-only services such as `cloudformation`, `lambda`, `rds`, or `elasticloadbalancing`.

## Required AWS Services

KNFSD File Cache requires access to the following AWS services:

| Service               | Endpoint Name                           | Purpose                                        |
|-----------------------|-----------------------------------------|------------------------------------------------|
| EC2                   | `com.amazonaws.<region>.ec2`            | Instance management, metadata                  |
| EC2 Messages          | `com.amazonaws.<region>.ec2messages`    | SSM Run Command, Patch Manager                 |
| Auto Scaling          | `com.amazonaws.<region>.autoscaling`    | Auto scaling group operations                  |
| CloudWatch Logs       | `com.amazonaws.<region>.logs`           | Log aggregation and monitoring                 |
| CloudWatch Monitoring | `com.amazonaws.<region>.monitoring`     | Metrics collection                             |
| Systems Manager       | `com.amazonaws.<region>.ssm`            | Instance management, parameter store           |
| SSM Messages          | `com.amazonaws.<region>.ssmmessages`    | Systems Manager communication                  |
| Secrets Manager       | `com.amazonaws.<region>.secretsmanager` | Secret retrieval (if using NetApp integration) |
| AWS STS               | `com.amazonaws.<region>.sts`            | IAM role assumption                            |
| AWS KMS               | `com.amazonaws.<region>.kms`            | Encryption key access                          |
| CloudWatch Events     | `com.amazonaws.<region>.events`         | Event-driven automation                        |

replace `<region>` with your AWS region, e.g. `us-east-1`.

### Cross-region endpoints (IAM and Route 53)

IAM and Route 53 are global AWS services that historically did not support PrivateLink in most regions. As of November 2025, both are reachable from any commercial-partition AWS region via [cross-region interface VPC endpoints](https://aws.amazon.com/blogs/networking-and-content-delivery/aws-privatelink-extends-cross-region-connectivity-to-aws-services/) hosted in `us-east-1`.

| Service   | Endpoint Name           | Service Region | Purpose                                        |
|-----------|-------------------------|----------------|------------------------------------------------|
| IAM       | `com.amazonaws.iam`     | `us-east-1`    | IAM control-plane API (global service)         |
| Route 53  | `com.amazonaws.route53` | `us-east-1`    | Route 53 control-plane API (global service)    |

The IAM principal that creates these endpoints must be allowed the `vpce:AllowMultiRegion` permission-only action. Any Service Control Policy (SCP) in your Organization must also allow `vpce:AllowMultiRegion`.

## Prerequisites

Before deploying KNFSD File Cache, ensure VPC endpoints are created if your subnets don't have internet access.

## Terraform Example

Here is some sample Terraform code to create the VPC Endpoints in a single subnet, before deploying KNFSD modules:

```hcl
variable "SUBNET" {
  description = "(Required) The single AWS Subnet ID to use for deployment of the VPC Endpoints. No default."
  type        = string
  nullable    = false
  validation {
    condition     = var.SUBNET != "" && can(regex("^subnet-[a-z0-9]{8,17}$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS Subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

# get the selected subnet
data "aws_subnet" "selected" {
  id = var.SUBNET
}

# get the VPC via selected subnet
data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

# local variables
locals {
  az             = data.aws_subnet.selected.availability_zone
  region         = regex("^([a-z]+-[a-z]+-[0-9]+)", local.az)[0]
  vpc_id         = data.aws_vpc.selected.id
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
  services = [
    "autoscaling",
    "ec2",
    "ec2messages",
    "events",
    "kms",
    "logs",
    "monitoring",
    "secretsmanager",
    "ssm",
    "ssmmessages",
    "sts"
  ]
  cross_region_services = [
    "iam",
    "route53"
  ]
  cross_region = "us-east-1"
}

# create security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "knfsd-vpc-endpoints-sg"
  description = "Security group for KNFSD VPC endpoints"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow all outbound"
  }

  tags = {
    Name = "knfsd-vpc-endpoints-sg"
  }
}

resource "aws_vpc_endpoint" "knfsd_endpoints" {
  for_each = toset(local.services)

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.SUBNET]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]

  tags = {
    Name = "knfsd-vpc-endpoint-${each.value}"
  }
}

resource "aws_vpc_endpoint" "knfsd_cross_region_endpoints" {
  for_each = toset(local.cross_region_services)

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${each.value}"
  service_region      = local.cross_region
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.SUBNET]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]

  tags = {
    Name = "knfsd-vpc-endpoint-${each.value}-${local.cross_region}"
  }
}
```

## Verification

After creating VPC endpoints, verify they're working:

```bash
# check endpoint status
aws ec2 describe-vpc-endpoints --region $KNFSD_REGION --vpc-endpoint-ids vpce-xxxxxxxxx

# test DNS resolution from an EC2 instance
nslookup <service-name>.$KNFSD_REGION.amazonaws.com
# example:
nslookup logs.us-east-1.amazonaws.com
nslookup iam.amazonaws.com
nslookup route53.amazonaws.com
```

## Troubleshooting

Common issues:

1. **DNS resolution fails**: Ensure `private_dns_enabled = true` is set
2. **Connection timeouts**: Check security group rules allow port 443
3. **Service unavailable**: Verify the VPC endpoint is in "Available" state

## Cost Considerations

VPC endpoints incur charges:

- **Per endpoint per hour**: ~$0.01 per hour per endpoint per AZ
- **Data processing**: ~$0.01 per GB processed
- **13 endpoints** (11 regional + 2 cross-region in `us-east-1`): ~$95/month base cost in a single AZ plus data transfer (minimal)
- **Cross-region data transfer**: cross-region endpoints additionally incur standard EC2 inter-region data transfer charges per GB. For IAM and Route 53 control-plane traffic this volume is typically very low.

For cost optimization in development environments, consider using NAT Gateway instead of VPC endpoints.
