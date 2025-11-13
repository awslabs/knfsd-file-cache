# FSx for OpenZFS Fanout (Network Load Balancer) Example

> WARNING: Ensure the **fanout** EC2 `INSTANCE_TYPE` is at least 2x-8x more powerful than the **cluster** EC2 `INSTANCE_TYPE` (use a larger size).

This example provides a `ZFS (source) <-> tier-1 (fanout) <-> NLB <-> tier-2 (cluster) <-> NLB` example of the multi-tier, [fanout](../../deployment/docs/fanout.md) architecture for KNFSD-File-Cache.

Amazon [FSx for OpenZFS](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/what-is.html) is a fully managed file storage service that supports the industry-standard NFS protocol (v3, v4.0, v4.1, v4.2).

A single fanout KNFSD proxy connects to a single-AZ (non-HA) FSx for OpenZFS filesystem, acting as the source filer. A second deployment of the KNFSD module is used to create a cluster of 3 x KNFSD proxies that connect to the fanout proxy fronted by a Network Load Balancer (NLB). This specific architecture could use NFS v3 as the FSxZ filesystem has a relatively small filehandle size (< 64 bytes). However, to demonstrate the use of NFS v4.1 with support for 128 bytes, we enforce NFS v4.1 throughout the deployment. The 2nd tier KNFSD proxies are fronted by another Network Load Balancer (NLB), which is the target for the NFS clients (not provisioned by this example) via the Terraform output `load_balancer_ip_address` or `load_balancer_dns_address`.

A single RDS PostgreSQL database is used to store the FSID database for the fanout proxy. This database is then reused for the cluster proxy. This improves efficiency (reduces number of resources to be managed), increase in speed of deployment, lowers operating cost, and ensures all the KNFSD proxy instances in the cluster allocate the same FSID to each export.

> WARNING: Lines marked with a `# comment` in the `main.tf` file are critical configuration to the deployment. Please review this file for additional details.

There are a number of ways to [monitor](../../docs/check-startup.md) the deployment progress.

## Security Groups

This example creates the necessary security groups for the flow of NFS traffic between the source (FSx ZFS filesystem) and `fanout` proxy, and between `fanout` proxy and `cluster` proxy (with NLB fronting each tier, both wrapped in their own security groups).

You will need to create or append to an existing security group(s) to allow for:

* NFS traffic; NFS clients to the `nfs_proxy_cluster` network load balancer (provided by the Terraform outputs)

See [Security Groups](../../deployment/docs/security-groups.md).

## Inputs

* `REGION` - (Required) The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`. No default.

* `SUBNET` - (Required) The single subnet ID to use for deployment of the FSx for OpenZFS source filer and KNFSD File Caches. Example: `subnet-038e337f0ff4cd53f`. No default.

* `PROXY_AMI` - (Required) The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script. No default.

* `KEY_NAME` - (Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: `""`.

* `INSTANCE_TYPE` - (Optional) The AWS EC2 instance type to use for the KNFSD cache. Default: `i3en.12xlarge`.

## Outputs

* `load_balancer_dns_address` - The DNS address of the Network Load Balancer that the NFS clients will connect to. Example: `lb-knfsd.nfsproxy-cluster.aws.internal`.

* `load_balancer_ip_address` - The IP address of the Network Load Balancer that the NFS clients will connect to.

## Additional Notes

You may be able to deploy the FSx for OpenZFS filesystem with a different deployment type, such as `SINGLE_AZ_2` which provides a single-AZ (non-HA) deployment with NVMe L2ARC cache. See [AWS Regions](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/available-aws-regions.html) for more details.
