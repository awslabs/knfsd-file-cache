# VPC Endpoints (AWS PrivateLink)

To **operate** KNFSD File Cache in a private subnet without internet connectivity (no IGW or NAT Gateway), the running KNFSD EC2 instances need access to some AWS service APIs. This document describes those AWS [PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html) (VPC) endpoints and how they map to KNFSD's runtime needs. An optional [VPC Endpoints Terraform module](../vpc-endpoints/README.md) is provided to deploy all of the endpoints described here automatically, which you can configure further as needed.

> INFO: This document covers only the runtime path of KNFSD itself. The Terraform host that performs `terraform apply` is assumed to run from a network with public AWS reachability and is therefore out of scope. The endpoints listed here do not cover the additional deployment-time-only services such as `cloudformation`, `lambda`, or `elasticloadbalancing`.

## Required AWS Services

KNFSD File Cache requires access to the following AWS services:

| Service               | Endpoint Name                           | Purpose                                        | Type      | Cost   |
|-----------------------|-----------------------------------------|------------------------------------------------|-----------|--------|
| DynamoDB              | `com.amazonaws.<region>.dynamodb`       | FSID database access                           | Gateway   | Free   |
| EC2                   | `com.amazonaws.<region>.ec2`            | Instance management, metadata                  | Interface | Billed |
| EC2 Messages          | `com.amazonaws.<region>.ec2messages`    | SSM Run Command, Patch Manager                 | Interface | Billed |
| Auto Scaling          | `com.amazonaws.<region>.autoscaling`    | Auto scaling group operations                  | Interface | Billed |
| CloudWatch Logs       | `com.amazonaws.<region>.logs`           | Log aggregation and monitoring                 | Interface | Billed |
| CloudWatch Monitoring | `com.amazonaws.<region>.monitoring`     | Metrics collection                             | Interface | Billed |
| Systems Manager       | `com.amazonaws.<region>.ssm`            | Instance management, parameter store           | Interface | Billed |
| SSM Messages          | `com.amazonaws.<region>.ssmmessages`    | Systems Manager communication                  | Interface | Billed |
| Secrets Manager       | `com.amazonaws.<region>.secretsmanager` | Secret retrieval (if using NetApp integration) | Interface | Billed |
| AWS STS               | `com.amazonaws.<region>.sts`            | IAM role assumption                            | Interface | Billed |
| AWS KMS               | `com.amazonaws.<region>.kms`            | Encryption key access                          | Interface | Billed |
| CloudWatch Events     | `com.amazonaws.<region>.events`         | Event-driven automation                        | Interface | Billed |

replace `<region>` with your AWS region, e.g. `us-east-1`.

> NOTE: The `com.amazonaws.<region>.<service>` form shown above applies to the AWS Commercial (`aws`) and GovCloud (`aws-us-gov`) partitions. In the AWS China (`aws-cn`) partition the interface endpoint service names are prefixed with `cn.`, e.g. `cn.com.amazonaws.<region>.secretsmanager`. The [VPC Endpoints Terraform module](../vpc-endpoints/README.md) resolves the correct, partition-specific service name automatically via the `aws_vpc_endpoint_service` data source, so it works unchanged in all three partitions.

### DynamoDB Gateway endpoint

The external FSID service (`FSID_MODE = "external"`, the default) stores the FSID mappings in an Amazon DynamoDB table, which the KNFSD instances reach via the regional DynamoDB API. In a private subnet without internet connectivity, create a DynamoDB **Gateway** VPC endpoint.

Unlike the interface endpoints above, gateway endpoints are **free of charge** (no hourly or data processing fees). They work by adding a route to the subnet's route table rather than provisioning an elastic network interface, so they attach to route tables instead of subnets and do not use a security group.

### Cross-region endpoints (IAM and Route 53)

IAM and Route 53 are global AWS services that historically did not support PrivateLink in most regions. As of November 2025, both are reachable from any commercial-partition AWS region via [cross-region interface VPC endpoints](https://aws.amazon.com/blogs/networking-and-content-delivery/aws-privatelink-extends-cross-region-connectivity-to-aws-services/) hosted in `us-east-1`.

| Service  | Endpoint Name           | Service Region | Purpose                                     | Type      | Cost   |
|----------|-------------------------|----------------|---------------------------------------------|-----------|--------|
| IAM      | `com.amazonaws.iam`     | `us-east-1`    | IAM control-plane API (global service)      | Interface | Billed |
| Route 53 | `com.amazonaws.route53` | `us-east-1`    | Route 53 control-plane API (global service) | Interface | Billed |

The IAM principal that creates these endpoints must be allowed the `vpce:AllowMultiRegion` permission-only action. Any Service Control Policy (SCP) in your Organization must also allow `vpce:AllowMultiRegion`.

> NOTE: These cross-region endpoints (hosted in `us-east-1` via `service_region`) are only offered in the AWS Commercial (`aws`) partition. The GovCloud (`aws-us-gov`) and China (`aws-cn`) partitions instead expose IAM and Route 53 as ordinary **same-region** interface endpoints using the same `com.amazonaws.iam` / `com.amazonaws.route53` service names but **without** the `service_region` attribute. The [VPC Endpoints Terraform module](../vpc-endpoints/README.md) handles both shapes automatically: it creates cross-region endpoints in the Commercial partition and same-region endpoints in GovCloud/China.

## Deploying the module

The endpoints described above are deployed by the optional [VPC Endpoints Terraform module](../vpc-endpoints/README.md). This module only needs to be deployed once per VPC, per AWS region, and must be deployed **before** the KNFSD modules if your subnets do not have internet access.

## Quick Deploy

```bash
cd knfsd-file-cache/deployment/vpc-endpoints
terraform init
terraform apply
```

See the [README](../vpc-endpoints/README.md) for the full list of inputs and outputs.

## Verification

The module's `endpoints_ready` output returns `true` once every expected endpoint (all interface endpoints plus the DynamoDB gateway endpoint) has been created, providing a quick success signal:

```bash
terraform output endpoints_ready
```

You can also verify the endpoints directly:

```bash
# check endpoint status
aws ec2 describe-vpc-endpoints --region $KNFSD_REGION --vpc-endpoint-ids vpce-xxxxxxxxx

# test DNS resolution from an EC2 instance
nslookup <service-name>.$KNFSD_REGION.amazonaws.com

# commercial / GovCloud examples:
nslookup logs.us-east-1.amazonaws.com
nslookup iam.amazonaws.com
nslookup route53.amazonaws.com

# China (aws-cn) examples:
nslookup logs.cn-north-1.amazonaws.com.cn
nslookup iam.amazonaws.com
nslookup route53.amazonaws.com
```

## Troubleshooting

Common issues:

1. **DNS resolution fails**: The module enables `private_dns_enabled` on every interface endpoint. Ensure no conflicting private hosted zone or resolver rule overrides the AWS service DNS names.
2. **Connection timeouts**: The module's security group allows inbound `443` from the VPC CIDR. Ensure the KNFSD instances' subnets fall within that CIDR and their own security groups permit outbound `443`.
3. **Service unavailable**: Verify the VPC endpoint is in "Available" state (or check the module's `endpoints_ready` output).

## Cost Considerations

VPC endpoints incur charges:

- **Per endpoint per hour**: ~$0.01 per hour per endpoint per AZ
- **Data processing**: ~$0.01 per GB processed
- **13 interface endpoints** total in every partition: 11 regional endpoints plus the 2 global IAM/Route 53 endpoints (cross-region in `us-east-1` for Commercial, same-region for GovCloud/China). Approximately ~$95/month base cost in a single AZ plus data transfer (minimal). The DynamoDB **gateway** endpoint is free and adds no cost.
- **Cross-region data transfer**: in the Commercial partition the cross-region IAM/Route 53 endpoints additionally incur standard EC2 inter-region data transfer charges per GB. For IAM and Route 53 control-plane traffic this volume is typically very low. GovCloud/China use same-region endpoints and so do not incur this inter-region charge.

For cost optimization in development environments, consider using NAT Gateway instead of VPC endpoints.
