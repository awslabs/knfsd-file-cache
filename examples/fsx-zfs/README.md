# FSx for OpenZFS Example

Amazon [FSx for OpenZFS](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/what-is.html) is a fully managed file storage service that supports the industry-standard NFS protocol (v3, v4.0, v4.1, v4.2).

This example provides a single KNFSD proxy connecting to a single-AZ (non-HA) FSx for OpenZFS filesystem to act as the source filer. We use NFS v3 for performance reasons.

There is a single ZFS volume in our deployment and we use the `EXPORT_HOST_AUTO_DETECT` feature to automatically detect the volume export via `showmount`. This is the root volume of the FSx for OpenZFS filesystem.

Although NOT used in this example, more detailed information on the `AUTO_EXPORT` feature can be found in the [Auto Re-export](../../deployment/docs/auto-re-export.md) documentation for handling `nohide`/`crossmnt` style nested mounts.

* `/fsx` - 1TB (root volume)

This example uses an `"external"` FSID database (Amazon DynamoDB) to ensure consistent file handle allocation, which is the recommended approach for production deployments.

We use `dns_round_robin` traffic mode to best-effort load balance the NFS clients across the KNFSD proxies.

There are a number of ways to [monitor](../../docs/check-startup.md) the deployment progress.

If deployment is successful (`knfsd-file-cache:status=ready`), you should see the following in the `/var/log/cloud-init-output.log` file via the `proxy-startup.sh` script:

```log
---- RUNNING: export auto-detect
Beginning processing of dynamically detected host exports (EXPORT_HOST_AUTO_DETECT)...
(Attempt 1/3) Mounting NFS share: fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx...
Created symlink /run/systemd/system/remote-fs.target.wants/rpc-statd.service → /usr/lib/systemd/system/rpc-statd.service.
NFS mount succeeded for fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx
Creating NFS share export for /fsx...
Finished creating NFS share export for /fsx
Finished processing of dynamically detected host exports (EXPORT_HOST_AUTO_DETECT)
---- DONE: 0h00m01s
...
### NFS Mounts ###
TARGET              SOURCE                                                     FSTYPE OPTIONS
/srv/nfs/fsx        fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx      nfs    rw,noatime,vers=3,rsize=1048576,wsize=1048576,namlen=255,acregmin=600,acregmax=600,acdirmin=600,acdirmax=600,hard,nocto,proto=tcp,nconnect=16,timeo=600,retrans=2,sec=sys,mountaddr=172.31.9.72,mountvers=3,mountport=20002,mountproto=tcp,fsc,local_lock=none,addr=172.31.9.72
### NFS Exports ###
exportfs: Reconnecting to fsid services
/fsx  172.31.0.0/16(sync,wdelay,nohide,no_subtree_check,fsid=1,reexport=auto-fsidnum,sec=sys,rw,secure,no_root_squash,no_all_squash)
...
INFO: Reached Proxy Startup Exit. Happy caching!
```

## Security Groups

This example creates a dedicated security group for the FSx for OpenZFS filesystem (proxy to source), allowing inbound NFS traffic from the proxy ASG security group.

You will need to create or append to existing security group(s) for:

* NFS traffic; NFS clients to proxy ASG

See [Security Groups](../../deployment/docs/security-groups.md).

## IAM Permissions

This example creates an Amazon FSx for OpenZFS file system (`aws_fsx_openzfs_file_system`) that is not covered by the project-wide IAM policies under [docs/iam/](../../docs/iam/). The additional `fsx:*` and `iam:CreateServiceLinkedRole` (for `fsx.amazonaws.com`) permissions required to deploy this example are provided in [iam.json](iam.json) and should be attached to the same principal that runs `terraform apply` for this example, alongside [docs/iam/tf-required.json](../../docs/iam/tf-required.json) and [docs/iam/tf-optional.json](../../docs/iam/tf-optional.json) (when applicable). See [docs/iam.md](../../docs/iam.md) for the full IAM reference.

As an alternative, if the role does not yet exist in the AWS account, you can pre-create the service-linked role for `fsx.amazonaws.com` before running `terraform apply` as follows:

```bash
aws iam create-service-linked-role --aws-service-name fsx.amazonaws.com
```

## Inputs

| Variable                  | Description                                                                                                                                | Required | Default           |
|---------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|----------|-------------------|
| `REGION`                  | The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`.                                                        | True     | No default        |
| `SUBNET`                  | The single subnet ID to use for deployment of the FSx for OpenZFS source filer and KNFSD File Caches. Example: `subnet-038e337f0ff4cd53f`. | True     | No default        |
| `PROXY_AMI`               | The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script.          | True     | No default        |
| `PROXY_BASENAME`          | Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a globally, unique basename to avoid conflicts.        | False    | `knfsd`           |
| `TRAFFIC_MODE`            | The traffic distribution mode to use for the KNFSD proxy cluster. The options are `dns_round_robin`, `loadbalancer`, or `none`.            | False    | `dns_round_robin` |
| `KEY_NAME`                | The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM.                                                       | False    | `""`              |
| `INSTANCE_TYPE`           | The AWS EC2 instance type to use for the KNFSD cache.                                                                                      | False    | `i3en.6xlarge`    |
| `KNFSD_NODES`             | The number of KNFSD instances to deploy as part of the cluster.                                                                            | False    | `1`               |
| `NUM_NFS_THREADS`         | The number of NFS threads to use for KNFSD.                                                                                                | False    | `128`             |
| `FSID_MODE`               | How to assign FSIDs (File System Identifiers) to each export. The options are `static`, `local`, or `external`.                            | False    | `external`        |
| `FSX_STORAGE_CAPACITY`    | The storage capacity of the FSx for OpenZFS source filer in GiB.                                                                           | False    | `1024`            |
| `FSX_THROUGHPUT_CAPACITY` | The throughput capacity of the FSx for OpenZFS source filer in MB/s.                                                                       | False    | `512`             |

## Outputs

| Output                                | Description                                                                                                                                            |
|---------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| `autoscaling_group_name`              | Name of the KNFSD proxy Auto Scaling Group.                                                                                                            |
| `autoscaling_group_security_group_id` | Security Group ID for the KNFSD proxy Auto Scaling Group.                                                                                              |
| `database_config`                     | Database configuration for the deployed DynamoDB FSID table. Only available when database is deployed by this module (when `FSID_MODE` is `external`). |
| `database_iam_policy`                 | The ARN of the IAM policy for DynamoDB table access. Only available when database is deployed by this module (when `FSID_MODE` is `external`).         |
| `dns_name`                            | The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`).            |
| `loadbalancer_ipaddress`              | The private IP address of the Network Load Balancer (when `TRAFFIC_MODE = "loadbalancer"`).                                                            |
| `knfsd_security_group_id`             | Security Group ID for the NFS clients to connect to the KNFSD proxy instances (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`).            |

## Additional Notes

You may be able to deploy the FSx for OpenZFS filesystem with a different deployment type, such as `SINGLE_AZ_2` which provides a single-AZ (non-HA) deployment with NVMe L2ARC cache. See [AWS Regions](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/available-aws-regions.html) for more details.
