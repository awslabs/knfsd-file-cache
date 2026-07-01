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

For further details see:

* [Reexporting NFS filesystems - Filehandle limits](https://www.kernel.org/doc/html/latest/filesystems/nfs/reexport.html#filehandle-limits)
* [NFS wiki - filehandle limits](https://linux-nfs.org/wiki/index.php/NFS_re-export#filehandle_limits)

## NFS transport metrics add up to the wrong value

Transport level metrics come from the transport (`xprt`) lines from `/proc/self/mountstats`.

While these metrics are reported per mount, the same transport may be shared by multiple mounts. This occurs because multiple mounts share the same source server, normally one TCP connection will be created per source server and shared by all the mounts. This can be changed by the `nconnect` value, for the KNFSD proxy this defaults to 16 TCP connections per source server.

If you sum the transport level metrics such as OTEL: `nfs.mount.ops_per_second` (CloudWatch: `knfsd/nfsiostat_ops_per_second`) the total value will be higher than expected due to counting the same TCP connection multiple times.

Where possible the per-operation statistics should be summarised as these will give the correct value.
