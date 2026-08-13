# Security Considerations

This document describes the security architecture and controls for KNFSD File Cache deployments on AWS. It covers encryption for data at rest and in transit, IAM policies and least-privilege access patterns, network isolation strategies, logging and monitoring integrations, and shared-responsibility considerations for compliance. Use this guide to understand the security posture of the solution and to align your deployment with your organization's security requirements.

## 1. Encryption at Rest and in Transit

### Encryption at Rest

KNFSD File Cache protects data at rest through AWS Key Management Service (AWS KMS) encryption of Amazon Machine Images (AMIs) and Amazon Elastic Block Store (EBS) volumes.

**AMI and EBS encryption (customer-managed keys):** The solution supports customer-managed KMS keys for AMI encryption, cross-region AMI distribution, and EBS volume encryption. Three encryption modes are available:

| Mode                 | Description                                                                                                   |
| -------------------- | ------------------------------------------------------------------------------------------------------------- |
| Default `aws/ebs`    | AWS-managed default EBS encryption key (no additional configuration)                                          |
| Customer-managed key | Specify a KMS Key ID via `KMS_KEY_ID` (Packer) or `EBS_KMS_KEY_ID` (Terraform) for full key-lifecycle control |
| Unencrypted          | Explicitly opt-out (not recommended for production)                                                           |

EBS volumes attached to KNFSD proxy instances (including NVMe instance store used for FS-Cache) are encrypted by default. When using customer-managed keys, the IAM policy includes the `KnfsdKms` Sid granting `kms:CreateGrant` and `kms:DescribeKey` permissions scoped to the specified key ARN. Customer-managed KMS keys and key policies are the customer's responsibility and are not created or managed by this project.

**Cross-region AMI distribution:** When distributing encrypted AMIs to multiple AWS regions via Packer (`DISTRIBUTION_REGIONS`), three key strategies are available through the `REGION_KMS_KEY_IDS` variable:

| Strategy                          | Configuration                                            | Trade-off                                                                                                      |
| --------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Default regional key              | Omit `REGION_KMS_KEY_IDS`                                | Simplest; each region uses its default `aws/ebs` key. No cross-account key sharing needed.                     |
| Per-region customer-managed key   | Map each region to a distinct CMK ARN                    | Strongest isolation; key compromise in one region does not affect others. Requires a KMS key per region.       |
| Multi-region customer-managed key | Map each region to replicas of a single multi-region CMK | Single key-policy to manage; consistent key ID across regions. Broader blast radius if the key is compromised. |

This allows customers to align their AMI encryption posture with organizational requirements around regional data sovereignty, key custody, and blast-radius containment.

**FSID database encryption:** When `FSID_MODE="external"`, the Amazon DynamoDB table storing filesystem identifier mappings uses server-side encryption at rest with the AWS-managed `aws/dynamodb` key by default, with point-in-time recovery enabled. There are no database credentials to store; access is authorized entirely through IAM.

**Secrets Manager:** Sensitive credentials (such as the NetApp `fsxadmin` password in the FSx for NetApp ONTAP integration) are stored in AWS Secrets Manager rather than in Terraform state or environment variables. The solution accesses secrets at runtime via IAM role-based authentication, avoiding static credential storage on disk.

### Encryption in Transit

**FSID database connections (HTTPS/SigV4):** All connections from KNFSD proxy instances to the Amazon DynamoDB FSID table use the regional DynamoDB HTTPS API (TLS) with AWS SigV4 request signing via the AWS SDK. There are no connection strings, database passwords, or server certificates to manage; the AWS SDK validates the service endpoint certificate against the standard AWS trust chain.

**NFS traffic:** NFS v3 and NFS v4 protocols transmit data over TCP/UDP without native encryption. KNFSD File Cache relies on network-level isolation (see Section 3) to protect NFS traffic in transit. For deployments requiring encrypted NFS traffic between on-premises source filers and AWS, customers should use AWS Site-to-Site VPN (IPSec) or AWS Direct Connect with MACsec encryption to protect the WAN segment.

**AWS API calls:** All communication between KNFSD proxy instances and AWS service endpoints (CloudWatch, Systems Manager, Secrets Manager, KMS, EC2, Auto Scaling) traverses HTTPS (TLS 1.2+). When operating in private subnets without internet connectivity, optional VPC Interface Endpoints (AWS PrivateLink) can be used to maintain TLS-encrypted paths to AWS APIs without traversing the public internet.

**NetApp REST API (FSx for NetApp ONTAP):** When automated export discovery is enabled, the solution validates the FSx for NetApp ONTAP CA certificate downloaded from the AWS certificate bundle. SSL certificate validation is enforced by default (`NETAPP_ALLOW_COMMON_NAME = false`), ensuring HTTPS connections to the NetApp management endpoint use proper SAN certificate verification.

## 2. IAM and Access Control

### Principle of Least Privilege

The KNFSD File Cache IAM model is designed around least-privilege access with separation of duties across two operational phases and an optional development/testing phase:

| Phase                                 | Policy File                             | Scope                                                                                                           |
| ------------------------------------- | --------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| AMI build (Packer) - required         | `docs/iam/packer.json`                  | EC2, Spot fleet, SSM parameter lookup, SSM Session Mgr tunnel, IAM PassRole (scoped to Packer instance profile) |
| AMI build (build instance) - optional | `docs/iam/packer-instance-profile.json` | Attached to the build instance's own role; SSM Session Manager agent registration and optional `ec2:CreateTags` |
| Deployment (Terraform) — required     | `docs/iam/tf-required.json`             | EC2 launch templates, Auto Scaling, SSM parameters, CloudWatch, Route 53, IAM roles/policies                    |
| Deployment (Terraform) — optional     | `docs/iam/tf-optional.json`             | DynamoDB, Secrets Manager, VPC endpoints, Network Load Balancer (attached only when feature flags are active)   |
| Testing (Smoke-Tests) - optional      | `docs/iam/testing.json`                 | EC2 Instance Connect (SSH-over-SSM) to reach ephemeral test instances                                           |

**Separation of duties:** The two operational phases can use a single combined IAM principal for simple setups, or be split across separate principals (one for AMI builds, one for deployments) for stronger isolation.

### Feature-Gated Permissions

The `tf-optional.json` policy contains Sids that should only be attached when their gating Terraform variable is enabled:

- `KnfsdDynamoDB` — required only when `FSID_DATABASE_DEPLOY = true` (also grants the data-plane reads used by the smoke-test assertions)
- `KnfsdSecretsManager` — required when using NetApp auto-detect with `NETAPP_SECRET != ""`
- `KnfsdLoadBalancer` / `KnfsdElbServiceLinkedRole` — required only when `TRAFFIC_MODE = "loadbalancer"`

The `testing.json` policy is optional and is only required to run the [smoke-tests](../image/smoke-tests/README.md) module:

- `KnfsdTestingSsmChannels` — required to poll the SSM agent online status
- `KnfsdTestingSsmStartSession` — required to open the SSH tunnel
- `KnfsdTestingSsmManageSession` — required to terminate the SSH tunnel
- `KnfsdTestingInstanceConnect` — required to push the short-lived ephemeral key via EC2 Instance Connect

The AMI build (Packer) can optionally tag the build instance with its progress via the `knfsd-file-cache:status` tag:

- Enabled only when `TAG_BUILD_STATUS = true`, which requires an `IAM_INSTANCE_PROFILE` whose role grants `ec2:CreateTags`. When disabled (default), the build requires no runtime credentials on the build instance.

The AMI build can also connect to the build instance over AWS Systems Manager Session Manager instead of inbound SSH:

- Enabled only when `SSH_INTERFACE = "session_manager"`, which requires an `IAM_INSTANCE_PROFILE` and the three `KnfsdPackerSessionManager*` Sids in `packer.json`. This removes the need for inbound port 22, a public IP address, and a bastion host: Packer creates a temporary security group but authorizes no ingress rule, and the tunnel is IAM-authenticated and auditable via AWS SSM session history. When the default SSH interface is used instead, those three Sids can be dropped. See [IAM Permissions](iam.md#packer-connection-method).

This approach ensures the deploying principal never holds more permissions than the selected feature set requires.

### Condition-Based Scoping

IAM policies are intentionally region-agnostic. Operators can further restrict scope by adding `aws:RequestedRegion` conditions to any Sid:

```json
{
    "Sid": "KnfsdCompute",
    "Effect": "Allow",
    "Action": ["ec2:CreateLaunchTemplate"],
    "Resource": "*",
    "Condition": {
        "StringEquals": {
            "aws:RequestedRegion": ["us-east-1"]
        }
    }
}
```

### Resource-Name Scoping

Several Sids scope `Resource` ARNs to the `knfsd-*` prefix (CloudFormation, Lambda, EventBridge, IAM roles/policies/instance-profiles, Secrets Manager, CloudWatch Logs). The default `PROXY_BASENAME` (`knfsd`) and database `NAME_PREFIX` (`knfsd-fsids`) align with these policies. Overriding these variables requires updating the `Resource` ARNs in the local copy of the IAM policies to match.

### Runtime IAM (Instance Profile)

KNFSD proxy EC2 instances run with a dedicated instance profile (`knfsd-instance-role`) that grants:

- SSM Parameter Store read access under `/knfsd/<cluster-name>` for runtime configuration
- CloudWatch Logs and Metrics write access for monitoring
- EC2 tag read access for instance metadata
- DynamoDB item-level access (when using external FSID database)
- Secrets Manager read access (when NetApp integration is enabled)
- KMS decrypt (when using encrypted EBS volumes)

**Bring-your-own IAM (restrictive environments):** Where the deploying role is denied `iam:CreateRole`/`iam:CreatePolicy`, set `EXISTING_INSTANCE_PROFILE_NAME` to a pre-created instance profile (and, in `dns_round_robin` mode, `EXISTING_LAMBDA_ROLE_ARN` for the `static_ip` Lambda). The module then creates no IAM roles or policies and uses the provided profile/role instead; ensuring the profile grants the permissions listed above becomes the customer's responsibility.

**Service-Linked Roles:** The Terraform module always requires `AWSServiceRoleForAutoScaling` (Auto Scaling group, used in every `TRAFFIC_MODE`) and additionally requires `AWSServiceRoleForElasticLoadBalancing` (Network Load Balancer) when `TRAFFIC_MODE = "loadbalancer"`. The module performs a read-only `iam:ListRoles` pre-flight check and fails early if a required role is absent, so an administrator can pre-create them manually once with:

```bash
aws iam create-service-linked-role --aws-service-name autoscaling.amazonaws.com
aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com
```

### Client-Side IAM (ENA Express)

NFS client instances that enable ENA Express (ENA-X) for high-throughput NFS paths require a minimal IAM policy with two actions:

- `ec2:DescribeInstanceTypes` — to check whether the instance type supports ENA-X
- `ec2:ModifyNetworkInterfaceAttribute` — to enable SRD on the primary ENI

Production deployments should further scope `ModifyNetworkInterfaceAttribute` to ENIs owned by the instance or within the specific VPC.

## 3. Network Isolation and Edge Protection

### VPC and Subnet Architecture

KNFSD File Cache is designed to operate entirely within private subnets. The solution does not require internet-facing resources; all AWS API access can be routed through VPC Interface Endpoints (AWS PrivateLink) when no NAT Gateway or Internet Gateway is present.

### Security Groups

The solution uses a layered security group model:

**Client-to-proxy security group:** Allows inbound NFS traffic from compute clients to the KNFSD proxy Auto Scaling Group on defined static ports:

| Port  | Protocol | Service         |
| ----- | -------- | --------------- |
| 111   | TCP/UDP  | RPC portmapper  |
| 2049  | TCP/UDP  | NFS             |
| 20048 | TCP/UDP  | mountd          |
| 20050 | TCP/UDP  | lockd-nlm       |
| 20051 | TCP/UDP  | statd           |
| 20053 | TCP/UDP  | lockd           |
| 20055 | TCP/UDP  | NFS v4 callback |

All NFS daemon ports are statically assigned (configured in `nfs-kernel-server`) to enable precise security group rules. Dynamic port negotiation is eliminated.

**Proxy-to-source security group:** Controls egress from KNFSD proxy instances to upstream NFS source filers. The specific ports depend on the source NFS server configuration.

**Load balancer security group** (only when `TRAFFIC_MODE = "loadbalancer"`): Controls inbound NFS traffic (TCP/UDP on all static NFS ports) to the Network Load Balancer from the VPC CIDR, with egress restricted to the VPC. Mirrors the client-to-proxy port set but scoped to the NLB.

**VPC endpoint security group:** Restricts inbound HTTPS (port 443) traffic to the VPC CIDR block, ensuring only VPC-internal resources can reach AWS service endpoints.

Source specification supports both VPC CIDR block ranges and security group ID references. Security group ID references are preferred for tighter isolation when the proxy security group ID is known (available via the Terraform output `knfsd_security_group_id`).

**Bring-your-own security group (restrictive environments):** Where the deploying role is denied `ec2:CreateSecurityGroup` (e.g. networking is managed centrally), set `EXISTING_SECURITY_GROUP_ID` to a pre-created security group. The module then creates no security group or ingress/egress rules and uses the provided group in the launch template; in `loadbalancer` mode the same group is reused for the Network Load Balancer. Configuring the required NFS ingress/egress rules on that group becomes the customer's responsibility.

### VPC Endpoints (AWS PrivateLink)

For operation in fully private subnets (no IGW or NAT), KNFSD File Cache requires Interface VPC Endpoints for 11 regional services and 2 cross-region global services:

**Regional endpoints:**

| Service               | Purpose                               |
| --------------------- | ------------------------------------- |
| EC2                   | Instance management, metadata         |
| EC2 Messages          | SSM Run Command                       |
| Auto Scaling          | ASG operations                        |
| CloudWatch Logs       | Log aggregation                       |
| CloudWatch Monitoring | Metrics collection                    |
| Systems Manager (SSM) | Instance management, parameter store  |
| SSM Messages          | SSM communication                     |
| Secrets Manager       | Secret retrieval (NetApp integration) |
| STS                   | IAM role assumption                   |
| KMS                   | Encryption key access                 |
| CloudWatch Events     | Event-driven automation               |

**Cross-region endpoints (hosted in `us-east-1`):**

| Service                            | Purpose                             |
| ---------------------------------- | ----------------------------------- |
| IAM (`com.amazonaws.iam`)          | IAM control-plane API (global)      |
| Route 53 (`com.amazonaws.route53`) | Route 53 control-plane API (global) |

The IAM principal creating cross-region endpoints requires the `vpce:AllowMultiRegion` permission-only action. Organization-level SCPs must also allow this action.

When using the default `FSID_MODE = "external"`, an Amazon DynamoDB **Gateway** endpoint is additionally required so the `knfsd-fsidd` daemon can reach the FSID table; see [VPC Endpoints](../deployment/docs/vpc-endpoints.md).

### WAN Connectivity (On-Premises to AWS)

For hybrid deployments where the source NFS filer resides on-premises, the solution supports:

- **AWS Direct Connect** — dedicated private connectivity with optional MACsec (Layer 2 encryption) for the physical link
- **AWS Site-to-Site VPN** — IPSec-encrypted tunnels over the public internet

Both approaches keep NFS traffic off the public internet and provide authenticated, encrypted transport for the WAN segment.

## 4. Logging, Monitoring, and Threat Detection

### Amazon CloudWatch Integration

KNFSD File Cache provides comprehensive observability through Amazon CloudWatch:

**CloudWatch Logs:** All KNFSD proxy instances ship logs to CloudWatch Logs groups under the `knfsd/` namespace. Log groups are pre-created during instance startup to avoid race conditions when multiple proxies boot simultaneously. Log rotation with size limits is configured at the OS level (`/var/log/*.log`, `/var/log/syslog`, systemd journal) to prevent local disk exhaustion.

**CloudWatch Metrics:** The solution publishes EC2 metrics via the CloudWatch Agent (`knfsd/ec2` namespace) and custom metrics via OpenTelemetry Collector (`knfsd/metrics` namespace), including:

- NFS server statistics (packets, threads, connections, clients)
- NFS mount/operation performance (RTT, RPC backlog, per-op metrics)
- NFS export throughput (operations, bytes, cache hit ratio)
- FS-Cache and NetfsLib counters (cookies, LRU, cache I/O, transfers)
- Cache memory footprint (NFS inode and dentry caches)
- EBS/NVMe disk I/O (IOPS, throughput, queue length, limit breaches)
- EC2 host health (CPU, memory, network, ENA-X/SRD)
- FSID daemon and DynamoDB performance (operations, queries, request latency, throttling, conflicts)

**CloudWatch Dashboards:** A versioned monitoring dashboard provides pre-built visualizations with ASG-level and instance-level drill-down, supporting pattern-variable linking for correlated analysis across Auto Scaling Group names, instance IDs, source and output NFS filer names.

**CloudWatch Alarms:** Configurable alarms on key health indicators (NFS thread exhaustion, health check failures) drive Auto Scaling actions.

### AWS Systems Manager

KNFSD proxy instances integrate with AWS Systems Manager for:

- **Session Manager** — secure shell access without SSH keys or bastion hosts; all sessions are logged
- **Run Command** — ad-hoc operational tasks across the fleet
- **Parameter Store** — runtime configuration under the `/knfsd/<cluster-name>` namespace; no secrets stored in user data or launch templates

### Audit and Access Logging

- **AWS CloudTrail** — captures all AWS API calls made by KNFSD IAM roles (instance profile, deployment principal, Lambda execution roles), providing an audit trail of infrastructure operations
- **VPC Flow Logs** — can be enabled on subnets hosting KNFSD proxy instances to capture network-level traffic metadata for forensic analysis and anomaly detection

### Threat Detection Compatibility

The KNFSD File Cache architecture is compatible with:

- **Amazon GuardDuty** — monitors for anomalous API activity, compromised instances, and malicious network behavior across the VPC
- **AWS Security Hub** — aggregates findings from GuardDuty, Inspector, and third-party tools for centralized security posture management

These services operate at the account/VPC level and require no solution-specific configuration.

## 5. Compliance and Shared-Responsibility Considerations

### AWS Shared Responsibility Model

KNFSD File Cache operates under the standard [AWS Shared Responsibility Model](https://aws.amazon.com/compliance/shared-responsibility-model/):

**AWS is responsible for:**

- Physical security of data centers
- Hardware and hypervisor isolation
- Network infrastructure security of the AWS global backbone
- Availability and security of managed services (DynamoDB, KMS, Secrets Manager, CloudWatch)

**The customer is responsible for:**

- Configuration of security groups, NACLs, and VPC routing
- IAM policy authorship and principal management
- KMS key policies and key rotation schedules
- Patch management of the KNFSD AMI (rebuilding the AMI with updated kernel and packages via Packer)
- NFS export policies and file-level access controls on source filers
- Enabling and configuring audit services (CloudTrail, VPC Flow Logs, GuardDuty)
- Encryption decisions (opting into customer-managed keys vs. AWS-managed keys)
- Network connectivity security for on-premises-to-AWS links (VPN/Direct Connect configuration)

### AMI and Patch Management

The KNFSD AMI is built from Ubuntu LTS using Packer with a custom-compiled Linux kernel optimized for NFS proxy workloads. Security patching follows this model:

1. **Kernel updates** — tracked in the CHANGELOG (e.g., v7.0.11-knfsd); customers rebuild the AMI via `packer build` and perform a rolling ASG update
2. **OS packages** — updated during Packer build; no automatic in-place patching on running instances
3. **Dependency updates** — Golang, Python, OpenTelemetry Collector, ENA driver, and other components are version-pinned and updated in each release

Customers should establish a cadence for AMI rebuilds aligned with their organization's patch management policy.

### Regulatory Compliance

The underlying AWS services used by KNFSD File Cache (EC2, DynamoDB, KMS, CloudWatch, Secrets Manager, Systems Manager) are in scope for major compliance programs including:

- SOC 1/2/3
- ISO 27001, 27017, 27018
- PCI DSS
- HIPAA (with a Business Associate Agreement)
- FedRAMP (in GovCloud regions)

However, compliance of the overall deployment depends on customer-side controls (IAM policies, encryption choices, logging enablement, access management). Customers operating in regulated environments should:

1. Enable CloudTrail with log file validation for tamper-evident audit trails
2. Enable VPC Flow Logs for network-level audit
3. Use customer-managed KMS keys for AMI/EBS encryption to maintain key-custody
4. Restrict IAM policies to the minimum required feature set
5. Scope security group source addresses to specific CIDR blocks rather than broad ranges
6. Deploy in private subnets with VPC endpoints (no internet path for data or control plane)

### Vulnerability Reporting

Security vulnerabilities in the KNFSD File Cache project should be reported via the [AWS Vulnerability Reporting](http://aws.amazon.com/security/vulnerability-reporting/) page or directly to [aws-security@amazon.com](mailto:aws-security@amazon.com). Do not create public GitHub issues for security reports.
