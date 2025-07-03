# Weka/Multiple Clusters Example

This example shows a 2 cluster KNFSD deployment, one mount for `/projects` and one for `/software`. Each module deploys a single KNFSD node per cluster, using DNS round-robin traffic distribution, and tuned for the required performance characteristics of either the faster changing metadata of project data or the slower changing application software, which typically consists of many small files. We use NFS v4.1 for `/projects`, and use a combination of NFS v3 (proxy to source), and NFS v4.1 (clients to proxy) for `/software` (together with a `nolock` mount option). We configure different metadata cache timeouts for each module to account for the different performance characteristics of the data they serve. We also use different EC2 instance types for performance and required NVMe cache capacity.

The deployment uses an external Amazon RDS PostgreSQL database per module, to store FSIDs to ensure all instances in each cluster allocate the same FSID to each export. A future enhancement could be to share a single RDS database for multiple clusters. See `var.FSID_DATABASE_DEPLOY` and `var.FSID_DATABASE_CONFIG` on how this could be achieved.

There are a number of ways to [monitor](../../docs/check-startup.md) the deployment progress.

## Security Groups

You will need to create or append to existing security group(s) for:

* NFS traffic; proxy to source
* NFS traffic; clients to proxy

See [Security Groups](../../deployment/docs/security-groups.md).

## Inputs

* `REGION` - (Required) The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`. No default.

* `SUBNET` - (Required) The single subnet ID to use for deployment of the KNFSD File Cache. Example: `subnet-038e337f0ff4cd53f`. No default.

* `PROXY_AMI` - (Required) The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script. No default.

* `WEKA_NFS_GATEWAY` - (Required) The IP address of the Weka NFS gateway. No default.

* `EXPORT_MAP_SOFTWARE` - (Required) A list of NFS SOFTWARE exports to mount from the source and re-export in the format `<SOURCE_IP>;<SOURCE_EXPORT>;<TARGET_EXPORT>`. See [KNFSD Deployment](../../deployment/README.md) for more details. No default.

## Outputs

* `projects_host` - DNS name of the KNFSD projects node for NFS clients to mount.

* `software_host` - DNS name of the KNFSD software node for NFS clients to mount.
