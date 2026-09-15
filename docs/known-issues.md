# Known Issues

## Showmount fails with "clnt_create: RPC: Program not registered"

When using `EXPORT_HOST_AUTO_DETECT` the proxy will attempt to mount all the exports from the source server using the `showmount` command.

```bash
$ showmount -e 172.31.1.62 # NFS client
$ showmount -e localhost # NFS server
clnt_create: RPC: Program not registered
```

This is caused by the NFS server not supporting NFSv3. Ensure `vers3=yes` is set in `/etc/nfs.conf.d/knfsd.conf` and is excluded from the `DISABLED_NFS_VERSIONS` parameter.

You can check the current running NFS server configuration:

```bash
# cat /proc/fs/nfsd/versions
-2 -3 +4 +4.1 +4.2
```

Alternatively, do not use `EXPORT_HOST_AUTO_DETECT` and use `EXPORT_MAP` to list the exports explicitly.

## Auto-detect skips exports that cannot be mounted

Some NFS servers advertise an export via `showmount -e` that cannot actually be mounted. For example, a NFSv4 pseudo-root `/` that returns `mount.nfs: access denied by server` when the proxy attempts to mount it.

When using `EXPORT_HOST_AUTO_DETECT`, the proxy attempts each advertised export with the standard 3 retries. If an individual export still cannot be mounted, it is skipped with a warning and startup continues with the remaining exports:

```text
WARNING: skipping auto-detected export 10.12.0.194:/; mount failed after retries
```

The proxy only aborts (`exit 1`) if **zero** auto-detected exports are mounted:

```text
ERROR: auto-detect (EXPORT_HOST_AUTO_DETECT) mounted zero exports; exiting
```

This tolerance is scoped to `EXPORT_HOST_AUTO_DETECT`. `EXPORT_MAP` and NetApp auto-detect (`ENABLE_NETAPP_AUTO_DETECT`) still fail immediately if any of their exports cannot be mounted, since those exports are requested explicitly.

To suppress the skip warning, add the unmountable path (e.g. `/`) to `EXCLUDED_EXPORTS` so it is filtered out before mounting. This is optional; auto-detect tolerates the unmountable export either way.

## rpc.mountd reports "can't stat exported dir"

When re-exporting NFS, `rpc.mountd` logs messages such as:

```text
rpc.mountd[9503]: authenticated mount request from 172.23.98.118:995 for /acme/home/<username> (/acme/home)
rpc.mountd[9503]: can't stat exported dir /acme/home/<username>: Success
```

These messages are benign and can be safely ignored. They occur because a client is mounting a subdirectory (e.g. `/acme/home/<username>`) within an exported parent path (`/acme/home`). The proxy's `rpc.mountd` calls `stat()` on the specific subdirectory path to verify it exists, but on a re-export proxy the subdirectory may not yet be materialised in the local VFS. The `stat()` fails, but `errno` is 0 so `strerror()` prints "Success", producing the confusing message.

The mount still succeeds because NFS resolves the path at the protocol level.

If home directories are automounted on the source server, the proxy may not be configured to access these directories, in which case the `stat()` failure is expected. NFS clients can still access these paths provided the parent export is correctly configured.

## Nested Mounts (aka crossmnt)

When the source server has nested mounts, each nested mount must be explicitly re-exported by the proxy so that the mount is assigned a unique `fsid`.

If the nested mount is not explicitly re-exported you will see one of two issues on the client:

* An empty directory.
* An I/O error trying to access the nested mount.

If this occurs, consider using auto-discovery to automatically find and mount all the exports from the source server.

If you're already using `EXPORT_HOST_AUTO_DETECT`, check that `showmount -e SOURCE-SERVER` lists all the nested mounts. If the source server does not reply with all the nested mounts then you might have to list the exports explicitly using `EXPORT_MAP`.

## Filehandle Limits

When a filehandle is too large, the client will receive general I/O errors or permission errors when trying to list, read or write files via the proxy.

NFSv3 only supports up to 64 bytes for a filehandle, and the proxy server adds up to an additional 25 bytes (22 bytes, rounded up to the nearest multiple of 4).

The largest filehandle that can be re-exported by NFSv3 is 42 bytes, for a total of 64 bytes. Some NFS servers such as NetApp (especially when using qtrees) use filehandles greater than 42 bytes, these filehandles cannot be re-exported using NFSv3.

To fix the issue, re-export using NFSv4 (the proxy can still mount the source using NFSv3). NFSv3 should be disabled on the proxy to avoid clients attempting to mount using a protocol that will fail.

```terraform
# Only enable NFS 4.1 on re-export
DISABLED_NFS_VERSIONS = "3,4.0,4.2"
```

For further details see [Resources](resources.md) for AWS articles, official guidance, and upstream Linux NFS documentation.

## NFS transport metrics add up to the wrong value

Transport level metrics come from the transport (`xprt`) lines from `/proc/self/mountstats`.

While these metrics are reported per mount, the same transport may be shared by multiple mounts. This occurs because multiple mounts share the same source server, normally one TCP connection will be created per source server and shared by all the mounts. This can be changed by the `nconnect` value, for the KNFSD proxy this defaults to 16 TCP connections per source server.

If you sum the transport level metrics such as OTEL: `nfs.mount.ops_per_second` (CloudWatch: `knfsd/nfsiostat_ops_per_second`) the total value will be higher than expected due to counting the same TCP connection multiple times.

Where possible the per-operation statistics should be summarised as these will give the correct value.

## Status tagging disabled when the EC2 API is unreachable

The `proxy-startup.sh` script reports its progress by setting the `knfsd-file-cache:status` tag on its own instance, which requires the proxy instance to reach the EC2 API (`ec2.<region>.amazonaws.com`).

A proxy instance in a private subnet with no NAT gateway, no public IP, and no `com.amazonaws.<region>.ec2` interface VPC endpoint cannot reach that endpoint. Status tagging is best-effort, so the first failed call disables tagging for the remainder of that boot and startup continues:

```text
WARNING: unable to set tag "knfsd-file-cache:status", disabling status tagging for this boot
WARNING: check the EC2 API is reachable (add a "com.amazonaws.ap-northeast-1.ec2" interface VPC endpoint, a NAT gateway, or a public IP) and that the instance role grants "ec2:CreateTags"
WARNING: startup continues and NFS caching is unaffected, but Terraform "ENABLE_STATUS_CHECK" and the AWS Console status column will not work
```

The warning is only emitted once per boot; the EC2 API is not called again after the first failure, so startup is not slowed down by repeated timeouts.

NFS caching is unaffected. Mounting the source, re-exporting, and serving clients need no EC2 API access. Only status reporting degrades:

* `ENABLE_STATUS_CHECK = true` waits for every instance to report `ready`, so it times out after 60 minutes. Leave it at the default of `false` in these environments, or restore EC2 API access. Note that `fanout` deployments require `ENABLE_STATUS_CHECK = true`.
* The `cluster_ready` module output, and any `depends_on` chained to it, cannot be used to gate downstream provisioning.
* The `knfsd-file-cache:status` column in the AWS Console stays at `starting`, the value set by the launch template.

Use the log based checks in [Check Proxy Startup](check-startup.md) to confirm the proxy started, either the `cloud-init` output log on the instance or the CloudWatch Logs copy of it.

The same warning appears when the EC2 API is reachable but the instance role does not grant `ec2:CreateTags`. This is worth checking when `EXISTING_INSTANCE_PROFILE_NAME` is set, since the module does not create or manage the policies on a user supplied instance profile.

## Startup fails to load parameters from SSM Parameter Store

Unlike status tagging, the SSM Parameter Store call is a hard requirement. The entire proxy configuration is read from `/knfsd/<cluster-name>`, so `proxy-startup.sh` exits immediately if it cannot be read:

```text
ERROR: failed to read parameters from SSM Parameter Store path /knfsd/knfsd-a1b2c3d4
ERROR: check the SSM API is reachable (add a "com.amazonaws.ap-northeast-1.ssm" interface VPC endpoint, a NAT gateway, or a public IP) and that the instance role grants "ssm:GetParametersByPath" for "/knfsd/knfsd-a1b2c3d4"
```

No VPC provides an implicit private path to the AWS service endpoints, so reaching `ssm.<region>.amazonaws.com` needs an internet gateway with a public IP, a NAT gateway, or a `com.amazonaws.<region>.ssm` interface VPC endpoint. See [VPC Endpoints](../deployment/docs/vpc-endpoints.md).

A related error is raised when the call succeeds but returns nothing:

```text
ERROR: no parameters found under /knfsd/knfsd-a1b2c3d4
ERROR: check "CLUSTER_NAME" matches the deployed cluster and the instance role grants "ssm:GetParametersByPath" for that path
```

This means the instance is talking to SSM but is looking at the wrong path, or the instance role is scoped to a different parameter hierarchy. Check the parameters exist with `aws ssm get-parameters-by-path --path /knfsd/<cluster-name> --recursive` using the same region as the instance.

## Performance degrades over time as FS-Cache backing files fragment

Read performance can degrade progressively over days or weeks of uptime. The symptoms are distinctive:

* CPU rises to 100% under client load and recovers when clients disconnect, so it is not permanently pinned.
* `cpu_usage_iowait` stays close to zero while `cpu_usage_active` saturates, so the NVMe or EBS cache device is not the constraint.
* Reading uncached files straight from the source filer is unaffected. Only cached reads are slow.
* It gets worse the longer the proxy has been up, and a cache reset resolves it.

`cachefiles` writes to its backing files using `O_DIRECT`, which bypasses XFS delayed allocation and speculative preallocation. Each cache write is therefore allocated immediately and in isolation, with no opportunity to merge with a logically adjacent write that has not happened yet. A backing file accumulates roughly one extent per cache write, so a large, heavily read file can reach hundreds of thousands of extents.

`SEEK_HOLE` is a linear scan of the extent list, and `cachefiles_prepare_read()` issues one per read subrequest to determine whether a range is already cached. Once a backing file is fully populated there is no hole to terminate the scan, so the scan runs to end of file. At around 200,000 extents a single `llseek()` can consume tens of milliseconds of CPU, which multiplied across thousands of reads per second saturates the instance.

Note that a cache which never reaches the `cachefilesd` cull threshold (roughly 80% used) never evicts a backing file, so extent counts only ever grow. A persistently half-full cache is therefore more exposed to this than a full one.

Check the current state on a proxy:

```bash
# mean extent length across the cache, and the worst single file
find /var/cache/fscache/cache -type f -size +1G -exec filefrag {} \; | sort -t: -k2 -rn | head

# extent count and populated ratio for one file
filefrag -v <backing-file> | tail -3
stat --format='apparent=%s allocated=%b*512' <backing-file>
```

The `FS-Cache: Mean Extents Length` and `FS-Cache: Max Extents per File` widgets on the CloudWatch dashboard track this directly, and `CPU per FS-Cache Read` isolates the per-read CPU cost.

The fix is the XFS extent size hint, exposed as the `CACHEFILESD_EXTSIZE` Terraform variable and applied to `/var/cache/fscache` at startup. It is the only allocation control that affects the `O_DIRECT` path, and it forces XFS to allocate in aligned multiples of the hint so neighbouring cache writes land in already-allocated space. The default of `8` MiB reduces extents on a 60 GiB file by roughly 8x.

The hint is inherited by files from their parent directory at creation time, so it only affects backing files created after it is applied. Existing fragmented files are not rewritten; they age out of the cache. Changing `CACHEFILESD_EXTSIZE` and running `terraform apply` updates the SSM parameter, and the new value is applied on the next instance boot via `xfs_io -c "extsize -D <bytes>"`, which recursively updates the mount point and every directory `cachefilesd` has already created.

There is a trade-off. Because the hint rounds each allocation up, XFS allocates more space than the data currently occupies, marking the surplus as an unwritten extent. That padding is consumed as the backing file fills, so the cost is highest on a cold cache and falls as it warms, and small files are unaffected because XFS bounds the hint by what the file actually needs. The `FS-Cache: Unwritten Capacity` widget measures this directly, in bytes. The cost scales with how far the hint exceeds the cache write size, so a larger hint wastes more: if the cache is close to full, or capacity stays high on a cache that is not filling, use a smaller value or `0` to disable the hint.
