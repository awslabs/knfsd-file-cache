# FAQ

## Error: Your query returned no results. Please change your search criteria and try again

This error occurs when the `PROXY_AMI` variable is set to an AMI ID that does not exist or is not accessible.

The AMI must be in the same AWS Region as the KNFSD proxy instances.

```hcl
│ Error: Your query returned no results. Please change your search criteria and try again.
│
│   with data.aws_ami.proxy,
│   on validations.tf line 9, in data "aws_ami" "proxy":
│    9: data "aws_ami" "proxy" {
```

## Error: The DB instance and EC2 security group are in different VPCs

```hcl
│ Error: creating RDS DB Instance (nfsproxy-fsids): operation error RDS: CreateDBInstance, https response error StatusCode: 400, RequestID: 150419e9-cbb0-4dc9-856e-4b8db915dd51, api error InvalidParameterCombination: The DB instance and EC2 security group are in different VPCs. The DB instance is in vpc-56786e19f2a7c041e and the EC2 security group is in vpc-1234ebfdfc54626ad
│
│   with module.nfs_proxy.module.fsid_database[0].aws_db_instance.fsids,
│   on ../database/main.tf line 64, in resource "aws_db_instance" "fsids":
│   64: resource "aws_db_instance" "fsids" {
```

If you are using a **non-default** VPC for the database, you have two options:

* Pre-create a DB subnet group in RDS (containing at least 2 subnets, each in a different availability zone, including the subnet defined in `var.SUBNET`) and then specify its name via `FSID_DB_SUBNET_GROUP_NAME`.
* Provide a list of 2+ subnet IDs (in different availability zones, including `var.SUBNET`) via `FSID_DB_SUBNET_IDS` and let the module create the `aws_db_subnet_group` for you.

The two variables are mutually exclusive. The single AZ deployment of the DB instance will still target the availability zone of the provided subnet via `var.SUBNET`. Please make sure to review the [FSID Database Options](../deployment/README.md#fsid-database-options) for the full table of scenarios and validation rules.

## Error creating resource: already exists

Some of the resources created by Terraform must have a globally unique name. When deploying multiple KNFSD proxy clusters in the same AWS region, you *MUST* give each KNFSD proxy cluster a unique `PROXY_BASENAME`. The default value of `nfsproxy` will have 8 random characters appended to the end of the name to make it unique, such as `nfsproxy-a1b2c3d4` if the default value is used.

## Proxy instances are replaced every 10 minutes

The KNFSD proxy instances in the Auto Scaling Group (ASG) never become healthy. When the initial grace period expires the instances are replaced. The initial grace period defaults to 10 minutes (600 seconds) and can be changed by setting `HEALTHCHECK_INITIAL_DELAY_SECONDS`. See [check the KNFSD proxy instance is starting correctly](./check-startup.md).

## Every file shows an I/O error in `ls`, or when trying to read/write

This could have one of two causes:

* The filehandle is too large to be re-exported.
* The directory is a nested mount (aka crossmnt).

If this happens for every file it is likely an issue with the filehandle. See "Filehandle Limits" in [Known Issues](known-issues.md).

If this only happens on some directories then it's likely an issue with nested mounts. See "Nested Mounts (aka crossmnt)" in [Known Issues](known-issues.md).

## Some directories are empty

Check if the directory is a nested mount on the source server (some NFS servers might refer to this by another name such as 'junction point').

See "Nested Mounts (aka crossmnt)" in [Known Issues](known-issues.md).

## What if the source server's IP address changes?

NFS resolves the IP address from the DNS or host name when the remote is mounted.

If the source server is restarted (e.g. due to failure) and a different IP address is allocated the proxies will need to be restarted.

If the clients connect via a load balancer they will be unaffected as the load balancer will reconnect the client to one of the new proxy instances.

If the clients connect to proxy instances directly (e.g. using DNS round robin) then the new proxy instances *MUST* have the same IP addresses (default behaviour).

In AWS, this can be achieved using "Detach/Attach Instance(s)" on the Auto Scaling Group. This will not affect the clients as the clients are connected via a load balancer. The load balancer will retain the same static IP. A custom, specific IPv4 address can be set for the load balancer via `LOADBALANCER_IP` if desired.

## What if the proxy's IP address changes?

NFS resolves the IP address from the DNS or host name when the proxy is mounted.

If the proxy is restarted (e.g. due to failure) and a different IP address then the clients will need to be restarted.

Ideally the clients will be connected to the proxy instances using a load balancer. The load balancer provides a static IP that does not change.

If the clients are connected directly to the proxy instances (e.g. using DNS round robin) then a Lambda function is deployed which handles the creation, allocation, tracking, and deletion of a static, private IPv4 address (from your VPC subnet) for each proxy instance automatically, and updates the DNS A record with the new IP address.

**NOTE:** It is technically possible to recover the clients without restarting but the process is complex. You need to kill any processes that are waiting on NFS operations and then remount the shares. Trying to do this across hundreds of clients is likely infeasible.

## What if the client loses connection to the proxy?

NFS resolves the IP address from the DNS or host name when the proxy is mounted.

If the proxy is restarted (e.g. due to failure) or the client cannot communicate with the proxy due to a network issue, the client will wait until the proxy recovers when using the `hard` option (recommended).

## What if the proxy loses connection to the source server?

Because the proxy is mounted using the `hard` option, the recovery behaviour is the proxy will wait indefinitely for the source to recover. Once the source is available the proxy will automatically resume function without any manual intervention.

This recovery may take up to 10 minutes (600 seconds), as per the NFS documentation on the `timeo` flag:

> For NFS over TCP the default timeo value is 600 (60 seconds). The NFS client performs linear backoff: After each retransmission the timeout is increased by timeo up to the maximum of 600 seconds.

## What if a proxy instance fails when using a Load Balancer?

If one of the proxy instances is restarted or replaced (e.g. due to failure) the load balancer will redirect the client to another proxy server that is online.

This will not require any manual intervention. The client will see this as a momentary interruption in the network and will re-establish a connection. This new connection will be routed to one of the other proxy instances that are online.

## What if the client loses connection to the Load Balancer?

The load balancer is using a static IP or the clients resolve the IP address from the DNS.

Because the client mounts the NFS volume using the `hard` option, if the client loses the connection in case of a network issue, the client will wait indefinitely for it to recover.

Once the issue is resolved the client will automatically resume function without any manual intervention.

## What if the entire KNFSD cluster fails?

There a few reasons why the entire cluster might be unavailable, such as:

* Instances restart while the source server is unavailable (start up script will fail to complete)
* Configuration/transient error, such as Terraform destroying, or scaling the Auto Scaling Group to zero.
* Missing Security Group rules to permit NFS traffic, or rules denying NFS traffic
* Misconfigured NACLs (optional) to permit or deny NFS traffic

Because the client mounts the NFS volume using the `hard` option, if the client loses the connection in case of a network issue, the client will wait indefinitely for it to recover.

Once the issue is resolved the client will automatically resume function without any manual intervention.

## Behaviour of `ls` changes when using the proxy

When going directly to the source server `ls` will show changes immediately, but when connecting through the proxy `ls` will continue to show cached changes. This isn't `ls` specific, as the behaviour is built into the kernel's `readdir` function. As any application that performs a directory listing should have the same behaviour.

This happens because `ls` initially bypasses the local cache on the client and always sends `GETATTR` to check the remote directory's `mtime`. If the `mtime` has changed then the client knows its cache is stale and performs a `READDIR`, otherwise the client can use its cache.

When using the proxy, the proxy cannot distinguish between a standard `GETATTR` that should be served from the metadata cache, and a `GETATTR` that is being used for cache invalidation.

`acdirmin` and `acdirmax` can be used to adjust directory metadata's expiry time on the proxy. Lowering this will force the proxy to re-validate the metadata with the source more often. This will result in the proxy detecting changes to the source more quickly but increase the number of metadata requests sent by the proxy to the source.

The proxy will still cache the `READDIR` results even after the directory metadata has expired. If the directory metadata (`mtime`) still matches the proxy will continue to use the cached `READDIR` results.

This behaviour is fully discussed in the test plan: [Difference in caching of directory listings between proxy and source](./tests/directory-listing.md).

## Supplementary Groups

The NFS protocol only supports a maximum of 16 supplementary (auxiliary) groups when using UNIX (`sec=sys`) authentication.

If your system relies on users with more than 16 supplementary groups the NFS proxy will need to be connected to LDAP so that the proxy can resolve the full list of groups for a user.

Once connected to LDAP you need to set:

```ini
[mountd]
manage-gids=yes
```

You can set this by either:

1. Changing `image/resources/etc/nfs.conf` and building a new image OR
2. Running `nfsconf --set mountd manage-gids yes` in a `CUSTOM_PRE_STARTUP_SCRIPT`.
