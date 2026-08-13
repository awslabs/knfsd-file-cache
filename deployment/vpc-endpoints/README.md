# KNFSD VPC Endpoints Module

This module supports deploying VPC endpoints for the KNFSD proxy cluster.

> NOTE: This module only needs to be deployed once per VPC, per AWS region.

## Quick Deploy

```bash
cd knfsd-file-cache/deployment/vpc-endpoints
terraform init
terraform apply
```

## Inputs

| Name                         | Description                                                                                                                                                                                                                                                                                                                                                                                             | Required | Default    |
|------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|------------|
| `REGION`                     | The AWS region for the deployment. Example: `us-east-1`.                                                                                                                                                                                                                                                                                                                                                | True     | No default |
| `SUBNETS`                    | One or more AWS Subnet IDs to use for deployment of the VPC interface endpoints. Each interface endpoint is created across every listed subnet (one ENI per subnet/AZ).<br><br>The DynamoDB gateway endpoint is not subnet-scoped and is associated with the route tables governing these subnets.                                                                                                      | True     | No default |
| `EXISTING_SECURITY_GROUP_ID` | ID of a pre-existing security group to attach to the KNFSD interface VPC endpoints instead of creating one.<br><br>When set, the module skips creating the security group and all of its ingress/egress rules; you are responsible for configuring the required HTTPS (443) ingress from the VPC CIDR on the provided security group. Required when the deploying role lacks `ec2:CreateSecurityGroup`. | False    | `""`       |

## Outputs

| Name                     | Description                                                                                                                                                                                                    |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `endpoint_service_names` | Resolved partition-correct service names for every endpoint created, for auditing which endpoints exist. Empty map if no endpoints are created.                                                                |
| `endpoints_ready`        | Boolean confirming every expected endpoint (regional interface + global + DynamoDB gateway) was created. A quick success signal for the deployment. `false` if the expected endpoint set cannot be determined. |
| `security_group_id`      | ID of the security group attached to all KNFSD interface VPC endpoints. Returns the module-created security group, or `EXISTING_SECURITY_GROUP_ID` when set.                                                   |
