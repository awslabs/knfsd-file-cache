# KNFSD File Cache Monitoring Dashboard

This module creates an Amazon CloudWatch dashboard for global monitoring of KNFSD proxy cluster(s) in any AWS commercial region running in your AWS account.

> NOTE: This module only needs to be deployed once per AWS account for all AWS regions, regardless of the number of KNFSD deployments you have in the account.

## Quick Deploy

```sh
cd knfsd-file-cache/deployment/metrics
terraform init
terraform apply
```

## Usage

To integrate the KNFSD metrics module into your own Terraform project, you should create a `deploy_metrics.tf` file in a separate directory outside of the KNFSD repository structure and add the following:

> NOTE: The order of [precedence](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration) will be used to determine the AWS Region to use for the deployment.

```terraform
# add a provider block if you wish to explicitly configure the AWS Region
provider "aws" {
  region = "us-east-1"
}

module "metrics" {
  source  = "github.com/awslabs/knfsd-file-cache/deployment/metrics?ref=v1.1.0-alpha.20"
}

# Print the name of the created CloudWatch dashboard
output "dashboard_name" {
  value = module.metrics.dashboard_name
}
```

## Deploy Metrics

Once you have created your `deploy_metrics.tf`, you can deploy the metrics dashboard with:

```sh
terraform init
terraform apply
```

## Outputs

| Output           | Description                                                        |
| ---------------- | ------------------------------------------------------------------ |
| `dashboard_name` | Name of the created CloudWatch dashboard                           |
| `dashboard_arn`  | The Amazon Resource Name (ARN) of the created CloudWatch dashboard |

## Filtering

The dashboard supports filtering by `Auto Scaling Group Name`, `Instance ID`, `RDS DB Instance Identifier`, and `Source NFS Filer` name pattern.

### Filtering Strategy

* **ASG_FILTER**: Auto Scaling Group Name
* **INSTANCE_FILTER**: Instance-level granularity available in applicable CloudWatch widgets
* **RDS_FILTER**: RDS DB Instance Identifier (if used)
* **SOURCE_FILTER**: Source NFS Filer

## Metrics Sources

The dashboard combines metrics from multiple sources:

### CloudWatch Agent Metrics (`knfsd/ec2` namespace)

The CloudWatch Agent collects system-level metrics from EC2 instances. Configuration is defined in `amazon-cloudwatch-agent.json`.

| Metric Name                                         | Description                                                         | Unit         | Period |
| --------------------------------------------------- | ------------------------------------------------------------------- | ------------ | ------ |
| `cpu_usage_active`                                  | CPU time spent in active (non-idle) states                          | Percent      | 60s    |
| `cpu_usage_iowait`                                  | CPU time spent waiting for I/O operations to complete               | Percent      | 60s    |
| `disk_free`                                         | Free disk space available                                           | Bytes        | 60s    |
| `disk_used_percent`                                 | Percentage of disk space used                                       | Percent      | 60s    |
| `diskio_write_bytes`                                | Total bytes written to disk                                         | Bytes        | 10s    |
| `diskio_read_bytes`                                 | Total bytes read from disk                                          | Bytes        | 10s    |
| `diskio_reads`                                      | Number of read operations completed                                 | Count        | 10s    |
| `diskio_writes`                                     | Number of write operations completed                                | Count        | 10s    |
| `diskio_io_time`                                    | Time spent processing I/O requests                                  | Milliseconds | 10s    |
| `diskio_ebs_ec2_instance_performance_exceeded_iops` | Time EBS IOPS exceeded EC2 instance performance limits              | Milliseconds | 10s    |
| `diskio_ebs_ec2_instance_performance_exceeded_tp`   | Time EBS throughput exceeded EC2 instance performance limits        | Milliseconds | 10s    |
| `diskio_ebs_volume_queue_length`                    | Number of I/O operations queued for EBS volumes                     | Count        | 10s    |
| `diskio_instance_store_performance_exceeded_iops`   | Time instance store IOPS exceeded performance limits                | Milliseconds | 10s    |
| `diskio_instance_store_performance_exceeded_tp`     | Time instance store throughput exceeded performance limits          | Milliseconds | 10s    |
| `diskio_instance_store_volume_queue_length`         | Number of I/O operations queued for instance store volumes          | Count        | 10s    |
| `ethtool_bw_in_allowance_exceeded`                  | Packets queued/dropped due to inbound bandwidth allowance exceeded  | Count        | 60s    |
| `ethtool_bw_out_allowance_exceeded`                 | Packets queued/dropped due to outbound bandwidth allowance exceeded | Count        | 60s    |
| `ethtool_conntrack_allowance_exceeded`              | Packets dropped due to connection tracking allowance exceeded       | Count        | 60s    |
| `ethtool_linklocal_allowance_exceeded`              | Packets dropped due to link-local service allowance exceeded        | Count        | 60s    |
| `ethtool_pps_allowance_exceeded`                    | Packets queued/dropped due to PPS allowance exceeded                | Count        | 60s    |
| `mem_cached`                                        | Memory used for filesystem cache                                    | Bytes        | 60s    |
| `mem_buffered`                                      | Memory used for buffers                                             | Bytes        | 60s    |
| `mem_available_percent`                             | Percentage of memory available for use                              | Percent      | 60s    |
| `net_bytes_recv`                                    | Total bytes received on network interface                           | Bytes        | 60s    |
| `net_bytes_sent`                                    | Total bytes sent on network interface                               | Bytes        | 60s    |
| `net_drop_in`                                       | Inbound packets dropped                                             | Count        | 60s    |
| `net_drop_out`                                      | Outbound packets dropped                                            | Count        | 60s    |
| `net_err_in`                                        | Inbound packet errors                                               | Count        | 60s    |
| `net_err_out`                                       | Outbound packet errors                                              | Count        | 60s    |
| `netstat_tcp_close_wait`                            | TCP connections in CLOSE_WAIT state                                 | Count        | 60s    |
| `netstat_tcp_established`                           | TCP connections in ESTABLISHED state                                | Count        | 60s    |
| `netstat_tcp_listen`                                | TCP connections in LISTEN state                                     | Count        | 60s    |
| `netstat_tcp_syn_sent`                              | TCP connections in SYN_SENT state                                   | Count        | 60s    |
| `netstat_tcp_time_wait`                             | TCP connections in TIME_WAIT state                                  | Count        | 60s    |
| `netstat_udp_socket`                                | Number of UDP sockets                                               | Count        | 60s    |
| `processes_blocked`                                 | Number of processes blocked waiting for I/O                         | Count        | 60s    |
| `processes_stopped`                                 | Number of stopped processes                                         | Count        | 60s    |
| `processes_total`                                   | Total number of processes                                           | Count        | 60s    |
| `processes_total_threads`                           | Total number of threads                                             | Count        | 60s    |
| `processes_zombies`                                 | Number of zombie processes                                          | Count        | 60s    |

### OpenTelemetry Metrics (`knfsd/metrics` namespace)

OpenTelemetry metrics are collected by the `knfsd-metrics-agent` and provide NFS-specific performance data.

#### Cache Metrics

| Metric Name                            | Description                                           | Stat    | Unit  | Period |
| -------------------------------------- | ----------------------------------------------------- | ------- | ----- | ------ |
| `knfsd/nfs_inode_cache_active_objects` | Number of active objects in the Linux NFS inode cache | Maximum | Count | 60s    |
| `knfsd/nfs_inode_cache_objsize`        | Total size of objects in the Linux NFS inode cache    | Maximum | Bytes | 60s    |
| `knfsd/dentry_cache_active_objects`    | Number of active objects in the Linux dentry cache    | Maximum | Count | 60s    |
| `knfsd/dentry_cache_objsize`           | Total size of objects in the Linux dentry cache       | Maximum | Bytes | 60s    |

#### Netfs Metrics

| Class   | Event  | Metric Name                           | Description                                    | Stat | Unit  | Period |
|---------|--------|---------------------------------------|------------------------------------------------|------|-------|--------|
| Reads   | DR=N   | `knfsd/netfs/reads/direct`            | Number of direct I/O read requests             | Sum  | Count | 30s    |
|         | RA=N   | `knfsd/netfs/reads/readahead`         | Number of readahead requests                   | Sum  | Count | 30s    |
|         | RF=N   | `knfsd/netfs/reads/folio`             | Number of read folio requests                  | Sum  | Count | 30s    |
|         | RS=N   | `knfsd/netfs/reads/single`            | Number of read single requests                 | Sum  | Count | 30s    |
|         | WB=N   | `knfsd/netfs/reads/write_begin`       | Number of write begin requests                 | Sum  | Count | 30s    |
|         | WBZ=N  | `knfsd/netfs/reads/write_zskip`       | Number of write zero skip operations           | Sum  | Count | 30s    |
| Writes  | BW=N   | `knfsd/netfs/writes/buffered`         | Number of buffered write requests              | Sum  | Count | 30s    |
|         | WT=N   | `knfsd/netfs/writes/writethrough`     | Number of writethrough requests                | Sum  | Count | 30s    |
|         | DW=N   | `knfsd/netfs/writes/direct`           | Number of direct I/O write requests            | Sum  | Count | 30s    |
|         | WP=N   | `knfsd/netfs/writes/pages`            | Number of write pages requests                 | Sum  | Count | 30s    |
|         | 2C=N   | `knfsd/netfs/writes/copy_to_cache`    | Number of copy to cache requests               | Sum  | Count | 30s    |
| DownOps | DL=N   | `knfsd/netfs/download/requests`       | Number of download requests                    | Sum  | Count | 30s    |
|         | ds=N   | `knfsd/netfs/download/done`           | Number of download operations completed        | Sum  | Count | 30s    |
|         | df=N   | `knfsd/netfs/download/failed`         | Number of download operations failed           | Sum  | Count | 30s    |
|         | di=N   | `knfsd/netfs/download/instead`        | Number of download instead of cache operations | Sum  | Count | 30s    |
| CaRdOps | RD=N   | `knfsd/netfs/cache_read/requests`     | Number of cache read requests                  | Sum  | Count | 30s    |
|         | rs=N   | `knfsd/netfs/cache_read/done`         | Number of cache read operations completed      | Sum  | Count | 30s    |
|         | rf=N   | `knfsd/netfs/cache_read/failed`       | Number of cache read operations failed         | Sum  | Count | 30s    |
| UpldOps | UL=N   | `knfsd/netfs/upload/requests`         | Number of upload requests                      | Sum  | Count | 30s    |
|         | us=N   | `knfsd/netfs/upload/done`             | Number of upload operations completed          | Sum  | Count | 30s    |
|         | uf=N   | `knfsd/netfs/upload/failed`           | Number of upload operations failed             | Sum  | Count | 30s    |
| CaWrOps | WR=N   | `knfsd/netfs/cache_write/requests`    | Number of cache write requests                 | Sum  | Count | 30s    |
|         | ws=N   | `knfsd/netfs/cache_write/done`        | Number of cache write operations completed     | Sum  | Count | 30s    |
|         | wf=N   | `knfsd/netfs/cache_write/failed`      | Number of cache write operations failed        | Sum  | Count | 30s    |
| ZeroOps | ZR=N   | `knfsd/netfs/zero_ops/zero`           | Number of zero read operations                 | Sum  | Count | 30s    |
|         | sh=N   | `knfsd/netfs/zero_ops/short`          | Number of short read operations                | Sum  | Count | 30s    |
|         | sk=N   | `knfsd/netfs/zero_ops/skip`           | Number of skip operations                      | Sum  | Count | 30s    |
| Retries | rq=N   | `knfsd/netfs/retries/read_req`        | Number of read request retries                 | Sum  | Count | 30s    |
|         | rs=N   | `knfsd/netfs/retries/read_subreq`     | Number of read subrequest retries              | Sum  | Count | 30s    |
|         | wq=N   | `knfsd/netfs/retries/write_req`       | Number of write request retries                | Sum  | Count | 30s    |
|         | ws=N   | `knfsd/netfs/retries/write_subreq`    | Number of write subrequest retries             | Sum  | Count | 30s    |
| Objs    | rr=N   | `knfsd/netfs/objects/read_reqs`       | Number of read request objects                 | Sum  | Count | 30s    |
|         | sr=N   | `knfsd/netfs/objects/subreqs`         | Number of subrequest objects                   | Sum  | Count | 30s    |
|         | foq=N  | `knfsd/netfs/objects/folio_queue`     | Number of folio queue objects                  | Sum  | Count | 30s    |
|         | wsc=N  | `knfsd/netfs/objects/write_conflicts` | Number of write stream conflicts               | Sum  | Count | 30s    |
| WbLock  | skip=N | `knfsd/netfs/wblock/skip`             | Number of writeback lock skips                 | Sum  | Count | 30s    |
|         | wait=N | `knfsd/netfs/wblock/wait`             | Number of writeback lock waits                 | Sum  | Count | 30s    |

See [Network Filesystem Services Library](https://www.kernel.org/doc/html/latest/filesystems/netfs_library.html) and [Netfs Library Stats](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/netfs/stats.c) for more information.

#### FS-Cache Metrics

| Class   | Event  | Metric Name                               | Description                                         | Stat | Unit  | Period |
|---------|--------|-------------------------------------------|-----------------------------------------------------|------|-------|--------|
| Cookies | n=N    | `knfsd/fscache/cookies/data`              | Number of data storage cookies allocated            | Sum  | Count | 30s    |
|         | v=N    | `knfsd/fscache/cookies/volume`            | Number of volume index cookies allocated            | Sum  | Count | 30s    |
|         | vcol=N | `knfsd/fscache/cookies/volume_collisions` | Number of volume index key collisions               | Sum  | Count | 30s    |
|         | voom=N | `knfsd/fscache/cookies/volume_oom`        | Number of OOM events when allocating volume cookies | Sum  | Count | 30s    |
| Acquire | n=N    | `knfsd/fscache/acquire/requests`          | Number of acquire cookie requests                   | Sum  | Count | 30s    |
|         | ok=N   | `knfsd/fscache/acquire/ok`                | Number of acquire requests that succeeded           | Sum  | Count | 30s    |
|         | oom=N  | `knfsd/fscache/acquire/oom`               | Number of acquire requests that failed (ENOMEM)     | Sum  | Count | 30s    |
| LRU     | n=N    | `knfsd/fscache/lru/count`                 | Number of cookies on the LRU                        | Sum  | Count | 30s    |
|         | exp=N  | `knfsd/fscache/lru/expired`               | Number of cookies expired off the LRU               | Sum  | Count | 30s    |
|         | rmv=N  | `knfsd/fscache/lru/removed`               | Number of cookies removed from the LRU              | Sum  | Count | 30s    |
|         | drp=N  | `knfsd/fscache/lru/dropped`               | Number of LRU'd cookies relinquished or withdrawn   | Sum  | Count | 30s    |
| Invals  | n=N    | `knfsd/fscache/invalidations`             | Number of cache invalidations                       | Sum  | Count | 30s    |
| Updates | n=N    | `knfsd/fscache/updates/requests`          | Number of update cookie requests                    | Sum  | Count | 30s    |
|         | rsz=N  | `knfsd/fscache/updates/resize`            | Number of resize requests                           | Sum  | Count | 30s    |
|         | rsn=N  | `knfsd/fscache/updates/resize_skipped`    | Number of skipped resize requests                   | Sum  | Count | 30s    |
| Relinqs | n=N    | `knfsd/fscache/relinquish/requests`       | Number of relinquish cookie requests                | Sum  | Count | 30s    |
|         | rtr=N  | `knfsd/fscache/relinquish/retire`         | Number of relinquish requests with retire=true      | Sum  | Count | 30s    |
|         | drop=N | `knfsd/fscache/relinquish/drop`           | Number of cookies no longer blocking re-acquisition | Sum  | Count | 30s    |
| NoSpace | nwr=N  | `knfsd/fscache/nospace/write`             | Number of write requests refused (no space)         | Sum  | Count | 30s    |
|         | ncr=N  | `knfsd/fscache/nospace/create`            | Number of create requests refused (no space)        | Sum  | Count | 30s    |
|         | cull=N | `knfsd/fscache/nospace/cull`              | Number of objects culled to make space              | Sum  | Count | 30s    |
| IO      | rd=N   | `knfsd/fscache/io/read`                   | Number of read operations in the cache              | Sum  | Count | 30s    |
|         | wr=N   | `knfsd/fscache/io/write`                  | Number of write operations in the cache             | Sum  | Count | 30s    |
|         | mis=N  | `knfsd/fscache/io/misfit`                 | Number of DIO misfit operations                     | Sum  | Count | 30s    |

See [FS-Cache](https://www.kernel.org/doc/html/latest/filesystems/caching/fscache.html) for more information.

#### Optional Metrics

| Metric Name                 | Description                                                 | Stat    | Unit    | Period |
| --------------------------- | ----------------------------------------------------------- | ------- | ------- | ------ |
| `knfsd/fscache/oldest_file` | Age of the oldest file in FS-Cache (NOT enabled by default) | Average | Seconds | 60s    |

#### NFS Server Metrics

| Metric Name                  | Description                                                                                         | Stat    | Unit  | Period |
| ---------------------------- | --------------------------------------------------------------------------------------------------- | ------- | ----- | ------ |
| `knfsd/nfs_connections`      | Number of active (ESTAB) NFS connections to the KNFSD proxy (1-16 per client, used for autoscaling) | Maximum | Count | 60s    |
| `knfsd/nfs_clients`          | Number of unique NFS client IP addresses connected to the KNFSD proxy (in any connected state)      | Maximum | Count | 60s    |
| `knfsd/nfs_packets_arrived`  | Number of NFS packets arrived                                                                       | Sum     | Count | 30s    |
| `knfsd/nfs_packets_deferred` | Number of NFS packets deferred                                                                      | Maximum | Count | 30s    |
| `knfsd/nfs_sockets_enqueued` | Number of times an NFS transport is enqueued to wait for an NFS thread to service                   | Sum     | Count | 30s    |
| `knfsd/nfs_threads`          | Number of current KNFSD server threads                                                              | Maximum | Count | 30s    |
| `knfsd/nfs_threads_timedout` | Number of times an NFS thread triggered an idle timeout                                             | Sum     | Count | 30s    |
| `knfsd/nfs_threads_woken`    | Number of times an idle NFS thread is woken to receive some data from an NFS transport              | Sum     | Count | 30s    |

* **packets-arrived**: Provides an accurate, workload-independent measure of the CPU load placed on the SUNRPC server layer due to NFS network traffic. Due to network stack effects, the value may differ from the actual NFS call count.
* **packets-deferred**: Indicates packets temporarily deferred because the NFS transport was already in use by an NFSD thread. This is inferred from: `packets-deferred = packets-arrived - ( sockets-enqueued + threads-woken )`.
* **sockets-enqueued**: The ideal rate of change is zero. Significantly non-zero values indicate a performance limitation: the workload is thread-limited. Configuring more NFSD threads will likely improve NFS performance when this counter is increasing.
* **threads-timedout**: Indicates more NFSD threads are configured than the workload requires. However, this is only a clue since the idle timeout is 60 minutes, making it less useful unless workload remains constant for hours. It's generally wise to maintain some slack for future load spikes.
* **threads-woken**: Tracks circumstances where incoming NFS work is being handled quickly (a good thing). The ideal rate of change should be close to, but less than, the `packets-arrived` rate.

See [Kernel NFS Server Statistics](https://www.kernel.org/doc/html/latest/filesystems/nfs/knfsd-stats.html) for more information.

#### NFS Mount Metrics (Proxy to Source Filer)

| Metric Name                            | Description                                                                | Stat    | Unit         | Period |
| -------------------------------------- | -------------------------------------------------------------------------- | ------- | ------------ | ------ |
| `knfsd/mount/read_bytes`               | Total bytes read from the source NFS server                                | Sum     | Bytes        | 60s    |
| `knfsd/mount/write_bytes`              | Total bytes written to the source NFS server                               | Sum     | Bytes        | 60s    |
| `knfsd/nfsiostat_mount_read_rtt`       | Average read operation RTT (Round Trip Time) per NFS mount                 | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_mount_write_rtt`      | Average write operation RTT per NFS mount                                  | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_mount_read_exe`       | Average read operation EXE (Execution Time) per NFS mount                  | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_mount_write_exe`      | Average write operation EXE per NFS mount                                  | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_rpc_backlog`          | RPC backlog size per NFS mount                                             | Maximum | Count        | 60s    |
| `knfsd/nfsiostat_ops_per_second`       | NFS operations per second to source server                                 | Sum     | Count        | 60s    |
| `knfsd/mount/operation/requests`       | Total number of NFS operation requests sent to source server               | Sum     | Count        | 60s    |
| `knfsd/mount/operation/sent_bytes`     | Total bytes sent to source server (includes RPC headers and payload)       | Sum     | Bytes        | 60s    |
| `knfsd/mount/operation/received_bytes` | Total bytes received from source server (includes RPC headers and payload) | Sum     | Bytes        | 60s    |
| `knfsd/mount/operation/major_timeouts` | Number of RPC major timeouts (default: 60s timeo)                          | Sum     | Count        | 60s    |
| `knfsd/mount/operation/errors`         | Number of RPC errors (requests with tk_status < 0)                         | Sum     | Count        | 60s    |

#### NFS Export Metrics (Client to Proxy)

| Metric Name                       | Description                                          | Stat | Unit  | Period |
| --------------------------------- | ---------------------------------------------------- | ---- | ----- | ------ |
| `knfsd/exports/total_operations`  | Total number of NFS operations received from clients | Sum  | Count | 60s    |
| `knfsd/exports/total_read_bytes`  | Total bytes read by NFS clients                      | Sum  | Bytes | 60s    |
| `knfsd/exports/total_write_bytes` | Total bytes written by NFS clients                   | Sum  | Bytes | 60s    |

#### FSID Daemon Metrics

| Metric Name                     | Description                                                                 | Stat    | Unit         | Period |
| ------------------------------- | --------------------------------------------------------------------------- | ------- | ------------ | ------ |
| `knfsd/fsid/operation/count`    | Number of operations performed by FSID daemon (each retry is one operation) | Sum     | Count        | 60s    |
| `knfsd/fsid/operation/duration` | Duration of each operation performed by FSID daemon                         | Average | Milliseconds | 60s    |
| `knfsd/fsid/request/count`      | Number of requests received by FSID daemon                                  | Sum     | Count        | 60s    |
| `knfsd/fsid/request/duration`   | Total duration of requests including all retries                            | Average | Milliseconds | 60s    |
| `knfsd/fsid/request/retries`    | Number of times each request was retried                                    | Sum     | Count        | 60s    |
| `knfsd/fsid/sql/query/count`    | Number of SQL queries executed by FSID daemon                               | Sum     | Count        | 60s    |
| `knfsd/fsid/sql/query/duration` | Duration of SQL queries executed by FSID daemon                             | Average | Milliseconds | 60s    |

### AWS Service Metrics

AWS-native service metrics from Amazon CloudWatch.

| Metric Name                                                 | Description                                          | Stat    | Unit                   | Period |
| ----------------------------------------------------------- | ---------------------------------------------------- | ------- | ---------------------- | ------ |
| `AWS/EC2.CPUUtilization`                                    | EC2 instance CPU utilization                         | Average | Percent                | 60s    |
| `AWS/EC2.NetworkIn`                                         | Network bytes received on all network interfaces     | Sum     | Bytes                  | 60s    |
| `AWS/EC2.NetworkOut`                                        | Network bytes sent on all network interfaces         | Sum     | Bytes                  | 60s    |
| `AWS/AutoScaling.GroupDesiredCapacity`                      | Desired capacity of Auto Scaling Group               | Average | Count                  | 60s    |
| `AWS/AutoScaling.GroupInServiceInstances`                   | Number of instances in service in Auto Scaling Group | Maximum | Count                  | 60s    |
| `AWS/RDS.DBLoad`                                            | Average number of active sessions                    | Average | Count                  | 60s    |
| `AWS/RDS.DBLoadNonCPU`                                      | Number of active sessions not waiting on CPU         | Average | Count                  | 60s    |
| `AWS/RDS.DBLoadCPU`                                         | Number of active sessions waiting on CPU             | Average | Count                  | 60s    |
| `AWS/RDS.DatabaseConnections`                               | Number of database connections                       | Average | Count                  | 60s    |
| `AWS/RDS.IamDbAuthConnectionRequests`                       | IAM database authentication connection requests      | Sum     | Count                  | 60s    |
| `AWS/RDS.IamDbAuthConnectionSuccess`                        | Successful IAM database authentications              | Sum     | Count                  | 60s    |
| `AWS/RDS.IamDbAuthConnectionFailure`                        | Failed IAM database authentications                  | Sum     | Count                  | 60s    |
| `AWS/RDS.IamDbAuthConnectionFailureThrottling`              | IAM auth failures due to throttling                  | Sum     | Count                  | 60s    |
| `AWS/RDS.IamDbAuthConnectionFailureServerError`             | IAM auth failures due to server errors               | Sum     | Count                  | 60s    |
| `AWS/RDS.IamDbAuthConnectionFailureInvalidToken`            | IAM auth failures due to invalid tokens              | Sum     | Count                  | 60s    |
| `AWS/RDS.IamDbAuthConnectionFailureInsufficientPermissions` | IAM auth failures due to insufficient permissions    | Sum     | Count                  | 60s    |
| `AWS/RDS.CPUUtilization`                                    | RDS instance CPU utilization                         | Average | Percent                | 60s    |
| `AWS/RDS.CPUCreditBalance`                                  | Accrued CPU credits available for bursting           | Average | Credits (vCPU-minutes) | 300s   |
| `AWS/RDS.CPUCreditUsage`                                    | CPU credits spent per measurement period             | Average | Credits (vCPU-minutes) | 300s   |
| `AWS/RDS.CPUSurplusCreditBalance`                           | Surplus CPU credits spent (unlimited mode)           | Average | Credits (vCPU-minutes) | 300s   |
| `AWS/RDS.CPUSurplusCreditsCharged`                          | Surplus CPU credits incurring charges                | Average | Credits (vCPU-minutes) | 300s   |
| `AWS/RDS.WriteIOPS`                                         | Write IOPS                                           | Average | Count/Second           | 60s    |
| `AWS/RDS.ReadIOPS`                                          | Read IOPS                                            | Average | Count/Second           | 60s    |
| `AWS/RDS.NetworkTransmitThroughput`                         | Network bytes sent                                   | Average | Bytes/Second           | 60s    |
| `AWS/RDS.NetworkReceiveThroughput`                          | Network bytes received                               | Average | Bytes/Second           | 60s    |
| `AWS/RDS.FreeableMemory`                                    | Available RAM                                        | Average | Bytes                  | 60s    |
| `AWS/RDS.SwapUsage`                                         | Swap space used                                      | Average | Bytes                  | 60s    |

## Dashboard Layout

The dashboard is organized into the following logical sections:

### Cache Overview

Overview of KNFSD caching layers including L1 (Linux filesystem cache) and L2 (FS-Cache).

| Widget                          | Metrics                                                          | Description                                                     | Stat    | Period | Label            |
| ------------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------- | ------- | ------ | ---------------- |
| Total READ Bytes                | `knfsd/exports/total_read_bytes`                                 | Total bytes read by clients to all proxies in ASG               | Sum     | 60s    | Bytes            |
| Total WRITE Bytes               | `knfsd/exports/total_write_bytes`                                | Total bytes written by clients to proxies in ASG                | Sum     | 60s    | Bytes            |
| Total BW                        | Expression: `ABS(RATE(SUM(m1)))`                                 | Total Bandwidth by clients to all proxies in ASG                | Sum     | 60s    | Bytes/Second     |
| Total IOPS                      | `knfsd/exports/total_operations`                                 | Total NFS operations from clients to all proxies in ASG         | Sum     | 60s    | Count            |
| Cache Hit Ratio %               | Expression: `IF(m2 > 0, (1 - (m1/m2)) * 100, 0)`                 | Percentage of reads served from cache (not fetched from source) | Sum     | 60s    | Percent %        |
| Cluster Size                    | `AWS/AutoScaling.GroupInServiceInstances`                        | Number of active proxy instances in ASG                         | Maximum | 60s    | Active Instances |
| FS-Cache Disk Used %            | `disk_used_percent` (path: `/var/cache/fscache`)                 | Percentage of FS-Cache disk space used                          | Maximum | 60s    | Percent %        |
| FS-Cache Disk Free Space        | `disk_free` (path: `/var/cache/fscache`)                         | Free space available in FS-Cache                                | Minimum | 60s    | Size             |
| FS-Cache Read Throughput        | `diskio_read_bytes` (device: `nvme0n1` or `nvme1n1` or `md127`)  | Disk read throughput for cache storage                          | Sum     | 10s    | Bytes/Second     |
| FS-Cache Write Throughput       | `diskio_write_bytes` (device: `nvme0n1` or `nvme1n1` or `md127`) | Disk write throughput for cache storage                         | Sum     | 10s    | Bytes/Second     |
| NFS Inode Cache Active Objects  | `knfsd/nfs_inode_cache_active_objects`                           | Number of cached NFS inodes                                     | Maximum | 60s    | Count            |
| NFS Inode Cache Object Size     | `knfsd/nfs_inode_cache_objsize`                                  | Total size of NFS inode cache                                   | Maximum | 60s    | Size             |
| NFS Dentry Cache Active Objects | `knfsd/dentry_cache_active_objects`                              | Number of cached directory entries                              | Maximum | 60s    | Count            |
| NFS Dentry Cache Object Size    | `knfsd/dentry_cache_objsize`                                     | Total size of dentry cache                                      | Maximum | 60s    | Size             |

**Thresholds:**

* FS-Cache Disk Used: 80% (brun/frun warning), 93% (bcull/fcull critical)

### Netfs Statistics

Performance metrics for NetfsLib operations.

| Widget            | Metrics                     | Description                                    | Stat | Period | Label |
|------------------ |-----------------------------|------------------------------------------------|------|--------|-------|
| NetfsLib: Reads   | `knfsd/netfs/reads/*`       | Direct, readahead, folio, single read requests | Sum  | 30s    | Count |
| NetfsLib: Writes  | `knfsd/netfs/writes/*`      | Buffered, writethrough, direct write requests  | Sum  | 30s    | Count |
| NetfsLib: DownOps | `knfsd/netfs/download/*`    | Download requests, done, failed, instead       | Sum  | 30s    | Count |
| NetfsLib: CaRdOps | `knfsd/netfs/cache_read/*`  | Cache read requests, done, failed              | Sum  | 30s    | Count |
| NetfsLib: UpldOps | `knfsd/netfs/upload/*`      | Upload requests, done, failed                  | Sum  | 30s    | Count |
| NetfsLib: CaWrOps | `knfsd/netfs/cache_write/*` | Cache write requests, done, failed             | Sum  | 30s    | Count |
| NetfsLib: ZeroOps | `knfsd/netfs/zero_ops/*`    | Zero, short, skip operations                   | Sum  | 30s    | Count |
| NetfsLib: Retries | `knfsd/netfs/retries/*`     | Read/write request and subrequest retries      | Sum  | 30s    | Count |
| NetfsLib: Objs    | `knfsd/netfs/objects/*`     | Read reqs, subreqs, folio queue, conflicts     | Sum  | 30s    | Count |
| NetfsLib: WbLock  | `knfsd/netfs/wblock/*`      | Writeback lock skips and waits                 | Sum  | 30s    | Count |

### FS-Cache Statistics

Performance metrics for FS-Cache operations.

| Widget            | Metrics                       | Description                                         | Stat | Period | Label |
|-------------------|-------------------------------|-----------------------------------------------------|------|--------|-------|
| FS-Cache: Cookies | `knfsd/fscache/cookies/*`     | Data and volume cookies allocated, collisions, OOM  | Sum  | 30s    | Count |
| FS-Cache: Acquire | `knfsd/fscache/acquire/*`     | Cookie acquire requests, succeeded, failed (ENOMEM) | Sum  | 30s    | Count |
| FS-Cache: LRU     | `knfsd/fscache/lru/*`         | LRU count, expired, removed, dropped cookies        | Sum  | 30s    | Count |
| FS-Cache: Invals  | `knfsd/fscache/invalidations` | Number of cache invalidations                       | Sum  | 30s    | Count |
| FS-Cache: Updates | `knfsd/fscache/updates/*`     | Update requests, resize, resize skipped             | Sum  | 30s    | Count |
| FS-Cache: Relinqs | `knfsd/fscache/relinquish/*`  | Relinquish requests, retire, drop                   | Sum  | 30s    | Count |
| FS-Cache: NoSpace | `knfsd/fscache/nospace/*`     | Write/create refused (no space), objects culled     | Sum  | 30s    | Count |
| FS-Cache: IO      | `knfsd/fscache/io/*`          | Cache read, write, misfit operations                | Sum  | 30s    | Count |

### NFS Server Metrics

Performance metrics for the KNFSD server.

| Widget                                     | Metrics                      | Description                                                                                   | Stat    | Period | Label |
| ------------------------------------------ | ---------------------------- | --------------------------------------------------------------------------------------------- | ------- | ------ | ----- |
| Proxy NFS Connections [established/active] | `knfsd/nfs_connections`      | Number of active (ESTAB) NFS connections to the proxy (1-16 per client, used for autoscaling) | Maximum | 60s    | Count |
| Proxy NFS Clients [connected/unique]       | `knfsd/nfs_clients`          | Number of unique NFS client IP addresses connected to the proxy (in any connected state)      | Maximum | 60s    | Count |
| NFS Packets Arrived                        | `knfsd/nfs_packets_arrived`  | Number of NFS packets arrived to the proxy                                                    | Sum     | 30s    | Count |
| NFS Packets Deferred                       | `knfsd/nfs_packets_deferred` | Number of NFS packets deferred by the proxy                                                   | Maximum | 30s    | Count |
| NFS Sockets Enqueued                       | `knfsd/nfs_sockets_enqueued` | Number of times an NFS transport is enqueued to wait for an NFS thread to service             | Sum     | 30s    | Count |
| NFS Threads                                | `knfsd/nfs_threads`          | Number of current KNFSD server threads                                                        | Maximum | 30s    | Count |
| NFS Threads Timed Out                      | `knfsd/nfs_threads_timedout` | Number of times an NFS thread triggered an idle timeout                                       | Sum     | 30s    | Count |
| NFS Threads Woken                          | `knfsd/nfs_threads_woken`    | Number of times an idle NFS thread is woken to receive some data from an NFS transport        | Sum     | 30s    | Count |

### Networking Activity

Network activity for KNFSD proxy nodes showing data flow to/from clients and source filers.

| Widget                    | Metrics                                              | Description                                        | Stat    | Period | Label       |
| ------------------------- | ---------------------------------------------------- | -------------------------------------------------- | ------- | ------ | ----------- |
| Proxy Ingress Traffic     | `net_bytes_recv`                                     | Total bytes received (data from on-premise/source) | Sum     | 60s    | Bytes       |
| Proxy Egress Traffic      | `net_bytes_sent`                                     | Total bytes sent (data to NFS clients)             | Sum     | 60s    | Bytes       |
| Cluster Network Bandwidth | `AWS/EC2.NetworkIn`, `AWS/EC2.NetworkOut` (ASG)      | Network throughput (entire cluster)                | Sum     | 60s    | Bits/Second |
| Proxy Network Bandwidth   | `AWS/EC2.NetworkIn`, `AWS/EC2.NetworkOut` (Instance) | Network throughput (individual proxy instance)     | Sum     | 60s    | Bits/Second |
| TCP/UDP Connection State  | `netstat_tcp_*`, `netstat_udp_socket`                | TCP and UDP connection states                      | Average | 60s    | Count       |

### Data Transfer

Data transfer metrics showing bandwidth between different layers.

| Widget                        | Metrics                           | Description                            | Stat | Period | Label        |
| ----------------------------- | --------------------------------- | -------------------------------------- | ---- | ------ | ------------ |
| Proxy to Source Bytes Read    | `knfsd/mount/read_bytes`          | Bytes read from source filer by proxy  | Sum  | 60s    | Bytes/Second |
| Client to Proxy Bytes Read    | `knfsd/exports/total_read_bytes`  | Bytes read by clients from proxy       | Sum  | 60s    | Bytes/Second |
| Proxy to Source Bytes Written | `knfsd/mount/write_bytes`         | Bytes written to source filer by proxy | Sum  | 60s    | Bytes/Second |
| Client to Proxy Bytes Written | `knfsd/exports/total_write_bytes` | Bytes written by clients to proxy      | Sum  | 60s    | Bytes/Second |

### NFS Latency & Stats

Performance metrics for NFS operations between proxy and source filer.

| Widget                           | Metrics                            | Description                                                   | Stat    | Period | Label             |
| -------------------------------- | ---------------------------------- | ------------------------------------------------------------- | ------- | ------ | ----------------- |
| Proxy to Source IOPS             | `knfsd/nfsiostat_ops_per_second`   | NFS operations per second to source                           | Sum     | 60s    | Operations/Second |
| Proxy to Source RPC Backlog Size | `knfsd/nfsiostat_rpc_backlog`      | Pending RPC requests to source                                | Maximum | 60s    | Count             |
| Proxy to Source Read RTT         | `knfsd/nfsiostat_mount_read_rtt`   | Round trip time for read operations                           | Average | 60s    | Time              |
| Proxy to Source Write RTT        | `knfsd/nfsiostat_mount_write_rtt`  | Round trip time for write operations                          | Average | 60s    | Time              |
| Proxy to Source Read EXE         | `knfsd/nfsiostat_mount_read_exe`   | Execution time for read operations (RTT + kernel processing)  | Average | 60s    | Time              |
| Proxy to Source Write EXE        | `knfsd/nfsiostat_mount_write_exe`  | Execution time for write operations (RTT + kernel processing) | Average | 60s    | Time              |

**Note:** RTT = Round Trip Time (network time), EXE = Execution Time (RTT + kernel processing time)

### NFS v3/v4 Operations

Detailed breakdown of NFS operations by operation type (GETATTR, READ, WRITE, etc.).

| Widget                  | Metrics                                               | Description                                    | Stat | Period | Label |
| ----------------------- | ----------------------------------------------------- | ---------------------------------------------- | ---- | ------ | ----- |
| NFS Ops: Sent Bytes     | `knfsd/mount/operation/sent_bytes` (by operation)     | Bytes sent for each NFS operation type         | Sum  | 60s    | Bytes |
| NFS Ops: Received Bytes | `knfsd/mount/operation/received_bytes` (by operation) | Bytes received for each NFS operation type     | Sum  | 60s    | Bytes |
| NFS Ops: Requests       | `knfsd/mount/operation/requests` (by operation)       | Number of requests for each NFS operation type | Sum  | 60s    | Count |
| NFS Ops: Major Timeouts | `knfsd/mount/operation/major_timeouts` (by operation) | Major timeouts for each NFS operation type     | Sum  | 60s    | Count |
| NFS Ops: Errors         | `knfsd/mount/operation/errors` (by operation)         | Errors for each NFS operation type             | Sum  | 60s    | Count |

**Supported NFS v3 Operations:** NULL, GETATTR, SETATTR, LOOKUP, ACCESS, READLINK, READ, WRITE, CREATE, MKDIR, SYMLINK, MKNOD, REMOVE, RMDIR, RENAME, LINK, READDIR, READDIRPLUS, FSSTAT, FSINFO, PATHCONF, COMMIT

**Supported NFS v4 Operations:** NULL, READ, WRITE, COMMIT, OPEN, OPEN_CONFIRM, OPEN_NOATTR, OPEN_DOWNGRADE, CLOSE, SETATTR, FSINFO, RENEW, SETCLIENTID, SETCLIENTID_CONFIRM, LOCK, LOCKT, LOCKU, ACCESS, GETATTR, LOOKUP, LOOKUP_ROOT, REMOVE, RENAME, LINK, SYMLINK, CREATE, PATHCONF, STATFS, READLINK, READDIR, SERVER_CAPS, DELEGRETURN, GETACL, SETACL, FS_LOCATIONS, RELEASE_LOCKOWNER, SECINFO, FSID_PRESENT, EXCHANGE_ID, CREATE_SESSION, DESTROY_SESSION, SEQUENCE, GET_LEASE_TIME, RECLAIM_COMPLETE, LAYOUTGET, GETDEVICEINFO, LAYOUTCOMMIT, LAYOUTRETURN, SECINFO_NO_NAME, TEST_STATEID, FREE_STATEID, GETDEVICELIST, BIND_CONN_TO_SESSION, DESTROY_CLIENTID, SEEK, ALLOCATE, DEALLOCATE, LAYOUTSTATS, CLONE, COPY, COPY_NOTIFY, GETXATTR, LISTXATTRS, LOOKUPP, OFFLOAD_CANCEL, READ_PLUS, REMOVEXATTR, SETXATTR, LAYOUTERROR

### Disk IO Performance

Performance statistics for NVMe or EBS volumes used for `/var/cache/fscache`.

| Widget                        | Metrics                                   | Description                                    | Stat | Period | Label             |
| ----------------------------- | ----------------------------------------- | ---------------------------------------------- | ---- | ------ | ----------------- |
| Disk IOPS                     | `diskio_reads`, `diskio_writes`           | Number of completed read/write operations      | Sum  | 10s    | Operations/Second |
| Bytes Transferred             | `diskio_read_bytes`, `diskio_write_bytes` | Total bytes read/written                       | Sum  | 10s    | Bytes/Second      |
| I/O Requests Queued           | `diskio_io_time`                          | Time I/O requests spent queued                 | Sum  | 10s    | Time (ms)         |
| Instance Performance Exceeded | `diskio_*_performance_exceeded_*`         | Time instance performance limits were exceeded | Sum  | 10s    | Count/Second      |
| Volume Queue Length           | `diskio_*_volume_queue_length`            | Number of operations queued at volume level    | Sum  | 10s    | Count             |

### EC2 Node Performance

General EC2 instance performance metrics.

| Widget                       | Metrics                                 | Description                                    | Stat    | Period | Label         |
| ---------------------------- | --------------------------------------- | ---------------------------------------------- | ------- | ------ | ------------- |
| CPU Utilization              | `AWS/EC2.CPUUtilization`                | EC2 instance CPU utilization                   | Average | 60s    | Percent %     |
| CPU Usage                    | `cpu_usage_active`, `cpu_usage_iowait`  | Detailed CPU usage breakdown                   | Average | 60s    | Percent %     |
| Memory Available             | `mem_available_percent`                 | Memory available for use                       | Average | 60s    | Percent %     |
| Memory Metrics               | `mem_buffered`, `mem_cached`            | Memory used for buffers and cache              | Average | 60s    | Bytes         |
| Network I/O                  | `net_drop_*`, `net_err_*`               | Network packet drops and errors                | Sum     | 60s    | Events/Second |
| ENA Performance              | `ethtool_*_allowance_exceeded`          | Packets queued/dropped due to allowance limits | Sum     | 60s    | Events/Second |
| Operating System Disk Used % | `disk_used_percent` (path: `/`)         | Root filesystem disk usage                     | Average | 60s    | Percent %     |
| Processes                    | `processes_*`                           | Process and thread statistics                  | Average | 60s    | Count         |

**Thresholds:**

* CPU Utilization: 80% (warning)
* Memory Available: 5% (warning)

### FSID Performance

KNFSD FSID daemon performance metrics for filesystem ID management.

| Widget             | Metrics                         | Description                                     | Stat    | Period | Label   |
| ------------------ | ------------------------------- | ----------------------------------------------- | ------- | ------ | ------- |
| Operation Count    | `knfsd/fsid/operation/count`    | Number of FSID operations by command and result | Sum     | 60s    | Count   |
| Operation Duration | `knfsd/fsid/operation/duration` | Duration of FSID operations                     | Average | 60s    | Time/ms |
| SQL Query Count    | `knfsd/fsid/sql/query/count`    | Number of SQL queries executed                  | Sum     | 60s    | Count   |
| SQL Query Duration | `knfsd/fsid/sql/query/duration` | Duration of SQL queries                         | Average | 60s    | Time/ms |
| Request Count      | `knfsd/fsid/request/count`      | Number of requests received                     | Sum     | 60s    | Count   |
| Request Duration   | `knfsd/fsid/request/duration`   | Total duration of requests including retries    | Average | 60s    | Time/ms |
| Request Retries    | `knfsd/fsid/request/retries`    | Number of request retries                       | Sum     | 60s    | Count   |

**Commands:** `get_fsidnum`, `get_or_create_fsidnum`, `get_path`
**SQL Queries:** `get_fsid`, `allocate_fsid`, `get_path`
**Results:** `ok`, `not_found`, `retry`

### RDS Database Performance

PostgreSQL RDS performance metrics for the FSID database.

| Widget                               | Metrics                                                         | Description                                | Stat    | Period | Label                  |
| ------------------------------------ | --------------------------------------------------------------- | ------------------------------------------ | ------- | ------ | ---------------------- |
| DB Load                              | `AWS/RDS.DBLoad`, `DBLoadCPU`, `DBLoadNonCPU`                   | Database active sessions                   | Average | 60s    | Active Sessions        |
| DB Connections                       | `AWS/RDS.DatabaseConnections`                                   | Number of database connections             | Average | 60s    | Count                  |
| DB IAM Auth                          | `AWS/RDS.IamDbAuth*`                                            | IAM authentication requests and results    | Sum     | 60s    | Count                  |
| DB CPU Utilization                   | `AWS/RDS.CPUUtilization`                                        | RDS instance CPU utilization               | Average | 60s    | Percent %              |
| DB EC2 CPU Credits (Credit Balance)  | `AWS/RDS.CPUCreditBalance`                                      | Accrued CPU credits available for bursting | Average | 300s   | Credits (vCPU-minutes) |
| DB EC2 CPU Credit Usage (Spend Rate) | `AWS/RDS.CPUCreditUsage`                                        | CPU credits spent per measurement period   | Average | 300s   | Credits (vCPU-minutes) |
| DB EC2 CPU Unlimited Credits         | `AWS/RDS.CPUSurplusCreditBalance`, `CPUSurplusCreditsCharged`   | Surplus CPU credits for unlimited mode     | Average | 300s   | Credits (vCPU-minutes) |
| DB IOPS                              | `AWS/RDS.ReadIOPS`, `WriteIOPS`                                 | Read and write IOPS                        | Average | 60s    | Count/Second           |
| DB Network Throughput                | `AWS/RDS.NetworkTransmitThroughput`, `NetworkReceiveThroughput` | Network throughput                         | Average | 60s    | Bytes/Second           |
| DB Memory                            | `AWS/RDS.FreeableMemory`, `SwapUsage`                           | Available memory and swap usage            | Average | 60s    | Bytes                  |

**Thresholds (`db.t4g.micro`):**

* CPU Credit Balance: 288 (max), 58 (20% warning), 29 (10% critical - fill below)
* CPU Credit Usage: 1.0/5min (baseline earn rate), 5.0 (5x baseline burst warning - fill above)
* Surplus Credits: 72 (25% warning), 288 (charge threshold - fill above)

> **Note:** Thresholds are configured for `db.t4g.micro` instance type which earns 12 credits/hour (1.0 per 5-minute period) with a maximum accrual of 288 credits (24-hour earn limit). CPU credit metrics are only available at 5-minute frequency. In unlimited mode, surplus credits exceeding 288 will incur additional charges. See [AWS T4g Instance Types](https://aws.amazon.com/ec2/instance-types/t4/) and [Burstable Performance Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances.html) for details.
