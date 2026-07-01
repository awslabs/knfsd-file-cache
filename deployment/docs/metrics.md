# Metrics

These deployment scripts can optionally configure the exporting of a range of custom metrics from each KNFSD node into [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/).

These are exported via a combination of the [Amazon CloudWatch Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/GettingStarted.html) and the [knfsd-metrics-agent](../../image/resources/knfsd-metrics-agent/README.md) which are both installed as part of the [build scripts](../../image/README.md).

These metrics are enabled by default via the `ENABLE_METRICS` variable.

> WARNING: **If you wish to use auto-scaling then metrics must be enabled**.

## Metrics Prerequisites

The following additional prerequisites must be met if you wish to enable metrics:

| Prerequisite                              | Details                                                                                                                                                                                                                                       |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Metrics Dashboard](../metrics/README.md) | If this is the first time you are deploying KNFSD in AWS, you need to setup the KNFSD Monitoring Dashboard. This is achieved via a standalone Terraform module and the process is described in the [metrics](../metrics/README.md) directory. |

## Exported Metrics

The following custom metrics are exported currently:

| Metric Name                                 | Description                                                                                                     |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **knfsd/nfs_connections**                   | The number of active (ESTAB) NFS connections to the KNFSD filer (1-16 per client, used for autoscaling).        |
| **knfsd/nfs_clients**                       | The number of unique NFS client IP addresses connected to the KNFSD filer (in any connected state).             |
| **knfsd/nfs_packets_arrived**               | The number of NFS packets arrived to the proxy.                                                                 |
| **knfsd/nfs_packets_deferred**              | The number of NFS packets deferred by the proxy.                                                                |
| **knfsd/nfs_sockets_enqueued**              | The number of times an NFS transport is enqueued to wait for an NFS thread to service.                          |
| **knfsd/nfs_threads**                       | The number of current KNFSD server threads.                                                                     |
| **knfsd/nfs_threads_timedout**              | The number of times an NFS thread triggered an idle timeout.                                                    |
| **knfsd/nfs_threads_woken**                 | The number of times an idle NFS thread is woken to receive some data from an NFS transport.                     |
| **knfsd/nfs_inode_cache_active_objects**    | The number of active objects in the Linux NFS inode cache.                                                      |
| **knfsd/dentry_cache_active_objects**       | The number of active objects in the Linux dentry cache.                                                         |
| **knfsd/nfs_inode_cache_objsize**           | The total size of the objects in the Linux NFS inode cache in bytes.                                            |
| **knfsd/dentry_cache_objsize**              | The total size of the objects in the Linux dentry cache in bytes.                                               |
| **knfsd/nfsiostat_mount_read_exe**          | The average read operation EXE per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).          |
| **knfsd/nfsiostat_mount_read_rtt**          | The average read operation RTT per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).          |
| **knfsd/nfsiostat_mount_write_exe**         | The average write operation EXE per NFS client mount over the past 60 seconds (KNFSD --> Output Filer).         |
| **knfsd/nfsiostat_mount_write_rtt**         | The average write operation RTT per NFS client mount over the past 60 seconds (KNFSD --> Output Filer).         |
| **knfsd/nfsiostat_ops_per_second**          | The number of NFS operations per second per NFS client mount over the past 60 seconds (KNFSD --> Source Filer). |
| **knfsd/nfsiostat_rpc_backlog**             | The RPC backlog per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).                         |
| **knfsd/mount/read_bytes**                  | The total number of bytes read from the source NFS server.                                                      |
| **knfsd/mount/write_bytes**                 | The total number of bytes written to the output NFS server.                                                     |
| **knfsd/mount/operation/requests**          | The total number of NFS requests sent to the source NFS server.                                                 |
| **knfsd/mount/operation/sent_bytes**        | The total number of bytes sent to the source NFS server. This includes the RPC protocol headers.                |
| **knfsd/mount/operation/received_bytes**    | The total number of bytes received from the source NFS server. This includes the RPC protocol headers.          |
| **knfsd/mount/operation/major_timeouts**    | The total number of RPC major timeouts (`timeo`, default 60 seconds) between the proxy and source NFS servers.  |
| **knfsd/mount/operation/errors**            | The total number of RPC errors between the proxy and the source NFS servers.                                    |
| **knfsd/exports/total_operations**          | The total number of NFS operations received from NFS clients.                                                   |
| **knfsd/exports/total_read_bytes**          | The total number of bytes read by NFS clients.                                                                  |
| **knfsd/exports/total_write_bytes**         | The total number of bytes written by NFS clients.                                                               |
| **knfsd/fscache/oldest_file**               | The age of the oldest file in FS-Cache. This metric is NOT enabled by default.                                  |
| **knfsd/fscache/acquire/ok**                | Number of acquire requests that succeeded.                                                                      |
| **knfsd/fscache/acquire/oom**               | Number of acquire requests that failed due to ENOMEM.                                                           |
| **knfsd/fscache/acquire/requests**          | Number of acquire cookie requests.                                                                              |
| **knfsd/fscache/cookies/data**              | Number of data storage cookies allocated.                                                                       |
| **knfsd/fscache/cookies/volume**            | Number of volume index cookies allocated.                                                                       |
| **knfsd/fscache/cookies/volume_collisions** | Number of volume index key collisions.                                                                          |
| **knfsd/fscache/cookies/volume_oom**        | Number of OOM events when allocating volume cookies.                                                            |
| **knfsd/fscache/invalidations**             | Number of invalidations.                                                                                        |
| **knfsd/fscache/io/misfit**                 | Number of DIO misfit operations.                                                                                |
| **knfsd/fscache/io/read**                   | Number of read operations in the cache.                                                                         |
| **knfsd/fscache/io/write**                  | Number of write operations in the cache.                                                                        |
| **knfsd/fscache/lru/count**                 | Number of cookies currently on the LRU.                                                                         |
| **knfsd/fscache/lru/dropped**               | Number of LRU'd cookies relinquished or withdrawn.                                                              |
| **knfsd/fscache/lru/expired**               | Number of cookies expired off of the LRU.                                                                       |
| **knfsd/fscache/lru/removed**               | Number of cookies removed from the LRU.                                                                         |
| **knfsd/fscache/nospace/create**            | Number of create requests refused due to lack of space.                                                         |
| **knfsd/fscache/nospace/cull**              | Number of objects culled to make space.                                                                         |
| **knfsd/fscache/nospace/write**             | Number of write requests refused due to lack of space.                                                          |
| **knfsd/fscache/relinquish/drop**           | Number of cookies no longer blocking re-acquisition.                                                            |
| **knfsd/fscache/relinquish/requests**       | Number of relinquish cookie requests.                                                                           |
| **knfsd/fscache/relinquish/retire**         | Number of relinquish requests with retire=true.                                                                 |
| **knfsd/fscache/updates/requests**          | Number of update cookie requests.                                                                               |
| **knfsd/fscache/updates/resize**            | Number of resize requests.                                                                                      |
| **knfsd/fscache/updates/resize_skipped**    | Number of skipped resize requests.                                                                              |
| **knfsd/netfs/cache_read/done**             | Number of cache read operations completed.                                                                      |
| **knfsd/netfs/cache_read/failed**           | Number of cache read operations failed.                                                                         |
| **knfsd/netfs/cache_read/requests**         | Number of cache read requests.                                                                                  |
| **knfsd/netfs/cache_write/done**            | Number of cache write operations completed.                                                                     |
| **knfsd/netfs/cache_write/failed**          | Number of cache write operations failed.                                                                        |
| **knfsd/netfs/cache_write/requests**        | Number of cache write requests.                                                                                 |
| **knfsd/netfs/download/done**               | Number of download operations completed.                                                                        |
| **knfsd/netfs/download/failed**             | Number of download operations failed.                                                                           |
| **knfsd/netfs/download/instead**            | Number of download instead of cache operations.                                                                 |
| **knfsd/netfs/download/requests**           | Number of download requests.                                                                                    |
| **knfsd/netfs/objects/folio_queue**         | Number of folio queue objects.                                                                                  |
| **knfsd/netfs/objects/read_reqs**           | Number of read request objects.                                                                                 |
| **knfsd/netfs/objects/subreqs**             | Number of subrequest objects.                                                                                   |
| **knfsd/netfs/objects/write_conflicts**     | Number of write stream conflicts.                                                                               |
| **knfsd/netfs/reads/direct**                | Number of direct I/O read requests.                                                                             |
| **knfsd/netfs/reads/folio**                 | Number of read folio requests.                                                                                  |
| **knfsd/netfs/reads/readahead**             | Number of readahead requests.                                                                                   |
| **knfsd/netfs/reads/single**                | Number of read single requests.                                                                                 |
| **knfsd/netfs/reads/write_begin**           | Number of write begin requests.                                                                                 |
| **knfsd/netfs/reads/write_zskip**           | Number of write zero skip operations.                                                                           |
| **knfsd/netfs/retries/read_req**            | Number of read request retries.                                                                                 |
| **knfsd/netfs/retries/read_subreq**         | Number of read subrequest retries.                                                                              |
| **knfsd/netfs/retries/write_req**           | Number of write request retries.                                                                                |
| **knfsd/netfs/retries/write_subreq**        | Number of write subrequest retries.                                                                             |
| **knfsd/netfs/upload/done**                 | Number of upload operations completed.                                                                          |
| **knfsd/netfs/upload/failed**               | Number of upload operations failed.                                                                             |
| **knfsd/netfs/upload/requests**             | Number of upload requests.                                                                                      |
| **knfsd/netfs/wblock/skip**                 | Number of writeback lock skips.                                                                                 |
| **knfsd/netfs/wblock/wait**                 | Number of writeback lock waits.                                                                                 |
| **knfsd/netfs/writes/buffered**             | Number of buffered write requests.                                                                              |
| **knfsd/netfs/writes/copy_to_cache**        | Number of copy to cache requests.                                                                               |
| **knfsd/netfs/writes/direct**               | Number of direct I/O write requests.                                                                            |
| **knfsd/netfs/writes/pages**                | Number of write pages requests.                                                                                 |
| **knfsd/netfs/writes/writethrough**         | Number of writethrough requests.                                                                                |
| **knfsd/netfs/zero_ops/short**              | Number of short read operations.                                                                                |
| **knfsd/netfs/zero_ops/skip**               | Number of skip operations.                                                                                      |
| **knfsd/netfs/zero_ops/zero**               | Number of zero read operations.                                                                                 |

## Dashboards

The KNFSD Metrics Dashboard is created automatically by the metrics initialisation Terraform that is detailed in the [Metrics Prerequisites](#metrics-prerequisites).

Once ran, you can then access the dashboard from [https://console.aws.amazon.com/cloudwatch](https://console.aws.amazon.com/cloudwatch/home#dashboards/).

## Custom Configuration

The metrics can be configured using the `METRICS_AGENT_CONFIG` variable in the Terraform module, or by customizing the metrics config when building the image.

Configuring the metrics using Terraform is the simplest option. You can provide the metrics configuration using a file or directly inline using heredoc.

Providing the metrics config from a file:

```terraform
module "knfsd" {
  source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.28"

  METRICS_AGENT_CONFIG = file("metrics-config.yaml")
}
```

Providing the metrics config inline using heredoc syntax:

```terraform
module "knfsd" {
  source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.28"

  METRICS_AGENT_CONFIG = <<- EOT
    receivers:
      mounts:
        collection_interval: 5m
  EOT
}
```

See the [knfsd-metrics-agent README](../../image/resources/knfsd-metrics-agent/README.md) for details on how to configure the metrics agent.
