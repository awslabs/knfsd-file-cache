# VPC Endpoints (AWS PrivateLink)

When deploying KNFSD File Cache in private subnets without internet connectivity, AWS [PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html) (VPC) endpoints are required to access AWS services. This document provides guidance on setting up VPC endpoints.

## Required AWS Services

KNFSD File Cache requires access to the following AWS services:

| Service               | Endpoint Name                           | Purpose                                        |
|-----------------------|-----------------------------------------|------------------------------------------------|
| EC2                   | `com.amazonaws.<region>.ec2`            | Instance management, metadata                  |
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
    "events",
    "kms",
    "logs",
    "monitoring",
    "secretsmanager",
    "ssm",
    "ssmmessages",
    "sts"
  ]
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
```

## AWS CLI Example

Alternatively, create VPC endpoints using AWS CLI:

```bash
# set variables
export KNFSD_REGION=<region-name>
export KNFSD_SUBNET=<subnet-id>

vpc_id=$(aws ec2 describe-subnets --region $KNFSD_REGION --subnet-ids $KNFSD_SUBNET --query 'Subnets[0].VpcId' --output text)
vpc_cidr=$(aws ec2 describe-vpcs --region $KNFSD_REGION --vpc-ids $vpc_id --query 'Vpcs[0].CidrBlock' --output text)

# create security group
sg_id=$(aws ec2 create-security-group \
  --region $KNFSD_REGION \
  --group-name knfsd-vpc-endpoints-sg \
  --description "Security group for KNFSD VPC endpoints" \
  --vpc-id $vpc_id \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=knfsd-vpc-endpoints-sg}]" \
  --output text --query 'GroupId')

# add ingress rule
aws ec2 authorize-security-group-ingress \
  --region $KNFSD_REGION \
  --group-id $sg_id \
  --protocol tcp \
  --port 443 \
  --cidr $vpc_cidr

# create VPC endpoints (via background threads)
for service in autoscaling ec2 events kms logs monitoring secretsmanager ssm ssmmessages sts; do
  aws ec2 create-vpc-endpoint \
    --region $KNFSD_REGION \
    --vpc-id $vpc_id \
    --service-name com.amazonaws.$KNFSD_REGION.$service \
    --vpc-endpoint-type Interface \
    --subnet-ids $KNFSD_SUBNET \
    --security-group-ids $sg_id \
    --private-dns-enabled \
    --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=knfsd-vpc-endpoint-$service}]" \
    &
done
```

## Verification

After creating VPC endpoints, verify they're working:

```bash
# check endpoint status
aws ec2 describe-vpc-endpoints --region $KNFSD_REGION --vpc-endpoint-ids vpce-xxxxxxxxx

# test DNS resolution from an instance
nslookup logs.$KNFSD_REGION.amazonaws.com
```

## Troubleshooting

Common issues:

1. **DNS resolution fails**: Ensure `private_dns_enabled = true` is set
2. **Connection timeouts**: Check security group rules allow port 443
3. **Service unavailable**: Verify the VPC endpoint is in "Available" state

## Cost Considerations

VPC endpoints incur charges:

- **Per endpoint per hour**: ~$0.01 per hour per endpoint
- **Data processing**: ~$0.01 per GB processed
- **10 endpoints**: ~$73/month base cost plus data transfer (minimal)

For cost optimization in development environments, consider using NAT Gateway instead of VPC endpoints.
