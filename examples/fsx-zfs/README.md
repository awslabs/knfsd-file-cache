# FSx for OpenZFS Example

Amazon [FSx for OpenZFS](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/what-is.html) is a fully managed file storage service that supports the industry-standard NFS protocol (v3, v4.0, v4.1, v4.2).

This example provides a single KNFSD proxy connecting to a single-AZ (non-HA) FSx for OpenZFS filesystem to act as the source filer. We use NFS v3 for performance reasons.

There are 3 ZFS volumes in our deployment and we use the `EXPORT_HOST_AUTO_DETECT` feature to automatically detect ALL the volume exports via `showmount`.

Although NOT used in this example, more detailed information on the `AUTO_EXPORT` feature can be found in the [Auto Re-export](../../deployment/docs/auto-re-export.md) documentation for handling `nohide`/`crossmnt` style nested mounts.

* `/fsx` - 1TB (root)
* `/fsx/vol2` - 1TB
* `/fsx/vol3` - 1TB

This example uses an `"external"` FSID database (RDS PostgreSQL) to ensure consistent file handle allocation, which is the recommended approach for production deployments.

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
(Attempt 1/3) Mounting NFS share: fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx/vol2...
NFS mount succeeded for fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx/vol2
Creating NFS share export for /fsx/vol2...
Finished creating NFS share export for /fsx/vol2
(Attempt 1/3) Mounting NFS share: fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx/vol3...
NFS mount succeeded for fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx/vol3
Creating NFS share export for /fsx/vol3...
Finished creating NFS share export for /fsx/vol3
Finished processing of dynamically detected host exports (EXPORT_HOST_AUTO_DETECT)
---- DONE: 0h00m01s
...
### NFS Mounts ###
TARGET              SOURCE                                                     FSTYPE OPTIONS
/srv/nfs/fsx        fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx      nfs    rw,noatime,vers=3,rsize=1048576,wsize=1048576,namlen=255,acregmin=600,acregmax=600,acdirmin=600,acdirmax=600,hard,nocto,proto=tcp,nconnect=16,timeo=600,retrans=2,sec=sys,mountaddr=172.31.9.72,mountvers=3,mountport=20002,mountproto=tcp,fsc,local_lock=none,addr=172.31.9.72
├─/srv/nfs/fsx/vol2 fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx/vol2 nfs    rw,noatime,vers=3,rsize=1048576,wsize=1048576,namlen=255,acregmin=600,acregmax=600,acdirmin=600,acdirmax=600,hard,nocto,proto=tcp,nconnect=16,timeo=600,retrans=2,sec=sys,mountaddr=172.31.9.72,mountvers=3,mountport=20002,mountproto=tcp,fsc,local_lock=none,addr=172.31.9.72
└─/srv/nfs/fsx/vol3 fs-0561426c51c39fbbc.fsx.eu-west-2.amazonaws.com:/fsx/vol3 nfs    rw,noatime,vers=3,rsize=1048576,wsize=1048576,namlen=255,acregmin=600,acregmax=600,acdirmin=600,acdirmax=600,hard,nocto,proto=tcp,nconnect=16,timeo=600,retrans=2,sec=sys,mountaddr=172.31.9.72,mountvers=3,mountport=20002,mountproto=tcp,fsc,local_lock=none,addr=172.31.9.72
### NFS Exports ###
exportfs: Reconnecting to fsid services
/fsx  172.31.0.0/16(sync,wdelay,nohide,no_subtree_check,fsid=1,reexport=auto-fsidnum,sec=sys,rw,secure,no_root_squash,no_all_squash)
/fsx/vol2  172.31.0.0/16(sync,wdelay,nohide,no_subtree_check,fsid=2,reexport=auto-fsidnum,sec=sys,rw,secure,no_root_squash,no_all_squash)
/fsx/vol3  172.31.0.0/16(sync,wdelay,nohide,no_subtree_check,fsid=3,reexport=auto-fsidnum,sec=sys,rw,secure,no_root_squash,no_all_squash)
...
INFO: Reached Proxy Startup Exit. Happy caching!
```

## Security Groups

This example creates a dedicated security group for the FSx for OpenZFS filesystem (proxy to source), allowing inbound NFS traffic from the proxy ASG security group.

You will need to create or append to existing security group(s) for:

* NFS traffic; NFS clients to proxy ASG

See [Security Groups](../../deployment/docs/security-groups.md).

## Inputs

* `REGION` - (Required) The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`. No default.

* `SUBNET` - (Required) The single subnet ID to use for deployment of the FSx for OpenZFS source filer and KNFSD File Caches. Example: `subnet-038e337f0ff4cd53f`. No default.

* `PROXY_AMI` - (Required) The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script. No default.

* `PROXY_BASENAME` - (Optional) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). Default: `nfsproxy`.

* `KEY_NAME` - (Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: `""`.

* `INSTANCE_TYPE` - (Optional) The AWS EC2 instance type to use for the KNFSD cache. Default: `i3en.6xlarge`.

* `KNFSD_NODES` - (Optional) The number of KNFSD instances to deploy as part of the cluster. Default: `1`.

* `FSID_MODE` - (Optional) How to assign FSIDs (File System Identifiers) to each export. The options are `static`, `local`, or `external`. Default: `external`.

## Outputs

* `autoscaling_group_name` - Name of the KNFSD proxy Auto Scaling Group.

* `proxy_dns_name` - DNS name of the KNFSD proxy.

## Additional Notes

You may be able to deploy the FSx for OpenZFS filesystem with a different deployment type, such as `SINGLE_AZ_2` which provides a single-AZ (non-HA) deployment with NVMe L2ARC cache. See [AWS Regions](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/available-aws-regions.html) for more details.
