# Known Issues

## Showmount fails with "clnt_create: RPC: Program not registered"

When using `EXPORT_HOST_AUTO_DETECT` the proxy will attempt to mount all the exports from the source server using the `showmount` command.

```bash
$ showmount -e 172.31.1.62 # NFS client
$ showmount -e localhost # NFS server
clnt_create: RPC: Program not registered
```

> INFO: Amazon EFS does not support `showmount` and only supports NFS v4.1.

This is caused by the NFS server not supporting NFSv3. Ensure `vers3=yes` is set in `/etc/nfs.conf.d/knfsd.conf` and is excluded from the `DISABLED_NFS_VERSIONS` parameter.

You can check the current running NFS server configuration:

```bash
# cat /proc/fs/nfsd/versions
-2 -3 +4 +4.1 +4.2
```

Alternatively, do not use `EXPORT_HOST_AUTO_DETECT` and use `EXPORT_MAP` to list the exports explicitly.

## rpc.mountd reports "can't stat exported dir"

When re-exporting NFS, `rpc.mountd` logs messages such as:

```text
rpc.mountd[9503]: authenticated mount request from 172.23.98.118:995 for /acme/home/<username> (/acme/home)
rpc.mountd[9503]: can't stat exported dir /acme/home/<username>: Success
```

These messages are benign and can be safely ignored. They occur because a client is mounting a subdirectory (e.g. `/acme/home/<username>`) within an exported parent path (`/acme/home`). The proxy's `rpc.mountd` calls `stat()` on the specific subdirectory path to verify it exists, but on a re-export proxy the subdirectory may not yet be materialised in the local VFS. The `stat()` fails, but `errno` is 0 so `strerror()` prints "Success", producing the confusing message.

The mount still succeeds because NFS resolves the path at the protocol level.

If home directories are automounted on the source server, the proxy may not be configured to access these directories, in which case the `stat()` failure is expected. NFS clients can still access these paths provided the parent export is correctly configured.

## Kernel NULL pointer dereference when restarting NFS server

When restarting the NFS server process the kernel might crash with "kernel NULL pointer dereference".

This is caused by a bug in the 6.11.0 HWE kernel for Ubuntu 24.04. This issue is fixed in later kernels (tested with 6.14.6 mainline), but these kernels are not yet available for Ubuntu 24.04.

To avoid restarting the NFS service the `unattended-upgrades` package has been removed for now.

See [kernel NULL pointer dereference: Workqueue: events_unbound nfsd_file_gc_worker, RIP: 0010:svc_wake_up+0x9/0x20](https://lore.kernel.org/linux-nfs/Z5VNJJUuCwFrl2Pj@eldamar.lan/).

```text
kernel: BUG: kernel NULL pointer dereference, address: 0000000000000090
kernel: #PF: supervisor read access in kernel mode
kernel: #PF: error_code(0x0000) - not-present page
kernel: PGD 14b3d9067 P4D 14b3d9067 PUD 14b3da067 PMD 0
kernel: Oops: Oops: 0000 [#1] PREEMPT SMP NOPTI
kernel: CPU: 8 UID: 0 PID: 231280 Comm: kworker/u67:2 Tainted: G        W          6.12.9-amd64 #1  Debian 6.12.9-1
kernel: Tainted: [W]=WARN
kernel: Hardware name: Supermicro AS -2014S-TR/H12SSL-i, BIOS 2.9 05/28/2024
kernel: Workqueue: events_unbound nfsd_file_gc_worker [nfsd]
kernel: RIP: 0010:svc_wake_up+0x9/0x20 [sunrpc]
kernel: Code: e1 bd ea 0f 0b e9 73 ff ff ff 0f 1f 80 00 00 00 00 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 f3 0f 1e fa 0f 1f 44 00 00 <48> 8b bf 90 00 00 00 f0 80 8f b8 00 00 00 01 e9 63 aa fe ff 0f 1f
kernel: RSP: 0018:ffffa9b9690abde8 EFLAGS: 00010286
kernel: RAX: 0000000000000001 RBX: ffff9d03f84f6c58 RCX: ffffa9b9690abe30
kernel: RDX: ffff9d034a5aa2a8 RSI: ffff9d034a5aa2a8 RDI: 0000000000000000
kernel: RBP: ffff9d034a5aa2a0 R08: ffff9d034a5aa2a8 R09: ffffa9b9690abe28
kernel: R10: ffff9d0451cff780 R11: 000000000000000f R12: ffffa9b9690abe30
kernel: R13: ffff9d034a5aa2a8 R14: ffff9d035451a000 R15: ffff9d034a5aa2a8
kernel: FS:  0000000000000000(0000) GS:ffff9d228ec00000(0000) knlGS:0000000000000000
kernel: CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
kernel: CR2: 0000000000000090 CR3: 0000000106e24003 CR4: 0000000000f70ef0
kernel: PKRU: 55555554
kernel: Call Trace:
kernel:  <TASK>
kernel:  ? __die_body.cold+0x19/0x27
kernel:  ? page_fault_oops+0x15a/0x2d0
kernel:  ? exc_page_fault+0x7e/0x180
kernel:  ? asm_exc_page_fault+0x26/0x30
kernel:  ? svc_wake_up+0x9/0x20 [sunrpc]
kernel:  ? srso_alias_return_thunk+0x5/0xfbef5
kernel:  nfsd_file_dispose_list_delayed+0xa7/0xd0 [nfsd]
kernel:  nfsd_file_gc_worker+0x190/0x2c0 [nfsd]
kernel:  process_one_work+0x177/0x330
kernel:  worker_thread+0x252/0x390
kernel:  ? __pfx_worker_thread+0x10/0x10
kernel:  kthread+0xd2/0x100
kernel:  ? __pfx_kthread+0x10/0x10
kernel:  ret_from_fork+0x34/0x50
kernel:  ? __pfx_kthread+0x10/0x10
kernel:  ret_from_fork_asm+0x1a/0x30
kernel:  </TASK>
```

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
