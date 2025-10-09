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
  source  = "github.com/awslabs/knfsd-file-cache/deployment/metrics?ref=v1.1.0-alpha.10"
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
| `dashboard_name` | Name of the created CloudWatch dashboard.                          |
| `dashboard_arn`  | The Amazon Resource Name (ARN) of the created CloudWatch dashboard.|

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
| `diskio_write_bytes`                                | Total bytes written to disk                                         | Bytes        | 30s    |
| `diskio_read_bytes`                                 | Total bytes read from disk                                          | Bytes        | 30s    |
| `diskio_reads`                                      | Number of read operations completed                                 | Count        | 30s    |
| `diskio_writes`                                     | Number of write operations completed                                | Count        | 30s    |
| `diskio_io_time`                                    | Time spent processing I/O requests                                  | Milliseconds | 30s    |
| `diskio_ebs_ec2_instance_performance_exceeded_iops` | Time EBS IOPS exceeded EC2 instance performance limits              | Milliseconds | 30s    |
| `diskio_ebs_ec2_instance_performance_exceeded_tp`   | Time EBS throughput exceeded EC2 instance performance limits        | Milliseconds | 30s    |
| `diskio_ebs_volume_queue_length`                    | Number of I/O operations queued for EBS volumes                     | Count        | 30s    |
| `diskio_instance_store_performance_exceeded_iops`   | Time instance store IOPS exceeded performance limits                | Milliseconds | 30s    |
| `diskio_instance_store_performance_exceeded_tp`     | Time instance store throughput exceeded performance limits          | Milliseconds | 30s    |
| `diskio_instance_store_volume_queue_length`         | Number of I/O operations queued for instance store volumes          | Count        | 30s    |
| `ethtool_bw_in_allowance_exceeded`                  | Packets queued/dropped due to inbound bandwidth allowance exceeded  | Count        | 60s    |
| `ethtool_bw_out_allowance_exceeded`                 | Packets queued/dropped due to outbound bandwidth allowance exceeded | Count        | 60s    |
| `ethtool_conntrack_allowance_exceeded`              | Packets dropped due to connection tracking allowance exceeded       | Count        | 60s    |
| `ethtool_linklocal_allowance_exceeded`              | Packets dropped due to link-local service allowance exceeded        | Count        | 60s    |
| `ethtool_pps_allowance_exceeded`                    | Packets queued/dropped due to PPS allowance exceeded                | Count        | 60s    |
| `mem_cached`                                        | Memory used for filesystem cache                                    | Bytes        | 60s    |
| `mem_buffered`                                      | Memory used for buffers                                             | Bytes        | 60s    |
| `mem_used_percent`                                  | Percentage of memory used                                           | Percent      | 60s    |
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
| `swap_used_percent`                                 | Percentage of swap space used                                       | Percent      | 60s    |

### OpenTelemetry Metrics (`knfsd/metrics` namespace)

OpenTelemetry metrics are collected by the `knfsd-metrics-agent` and provide NFS-specific performance data.

#### NFS Connections

| Metric Name             | Description                                                               | Stat    | Unit  | Period |
| ----------------------- | ------------------------------------------------------------------------- | ------- | ----- | ------ |
| `knfsd/nfs_connections` | Number of NFS clients connected to the KNFSD proxy (used for autoscaling) | Maximum | Count | 60s    |

#### Cache Metrics

| Metric Name                            | Description                                           | Stat    | Unit  | Period |
| -------------------------------------- | ----------------------------------------------------- | ------- | ----- | ------ |
| `knfsd/nfs_inode_cache_active_objects` | Number of active objects in the Linux NFS inode cache | Average | Count | 60s    |
| `knfsd/nfs_inode_cache_objsize`        | Total size of objects in the Linux NFS inode cache    | Average | Bytes | 60s    |
| `knfsd/dentry_cache_active_objects`    | Number of active objects in the Linux dentry cache    | Average | Count | 60s    |
| `knfsd/dentry_cache_objsize`           | Total size of objects in the Linux dentry cache       | Average | Bytes | 60s    |

#### NFS Mount Metrics (Proxy to Source Filer)

| Metric Name                            | Description                                                                | Stat    | Unit         | Period |
| -------------------------------------- | -------------------------------------------------------------------------- | ------- | ------------ | ------ |
| `knfsd/mount/read_bytes`               | Total bytes read from the source NFS server                                | Sum     | Bytes        | 60s    |
| `knfsd/mount/write_bytes`              | Total bytes written to the source NFS server                               | Sum     | Bytes        | 60s    |
| `knfsd/nfsiostat_mount_read_rtt`       | Average read operation RTT (Round Trip Time) per NFS mount                 | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_mount_write_rtt`      | Average write operation RTT per NFS mount                                  | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_mount_read_exe`       | Average read operation EXE (Execution Time) per NFS mount                  | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_mount_write_exe`      | Average write operation EXE per NFS mount                                  | Average | Milliseconds | 60s    |
| `knfsd/nfsiostat_rpc_backlog`          | RPC backlog size per NFS mount                                             | Average | Count        | 60s    |
| `knfsd/mount/operation/requests`       | Total number of NFS operation requests sent to source server               | Sum     | Count        | 60s    |
| `knfsd/mount/operation/sent_bytes`     | Total bytes sent to source server (includes RPC headers and payload)       | Sum     | Bytes        | 60s    |
| `knfsd/mount/operation/received_bytes` | Total bytes received from source server (includes RPC headers and payload) | Sum     | Bytes        | 60s    |
| `knfsd/mount/operation/major_timeouts` | Number of RPC major timeouts (default: 60s timeo)                          | Sum     | Count        | 60s    |
| `knfsd/mount/operation/errors`         | Number of RPC errors (requests with tk_status < 0)                         | Sum     | Count        | 60s    |

#### NFS Export Metrics (Client to Proxy)

| Metric Name                      | Description                                          | Stat | Unit  | Period |
| -------------------------------- | ---------------------------------------------------- | ---- | ----- | ------ |
| `knfsd/exports/total_operations` | Total number of NFS operations received from clients | Sum  | Count | 60s    |
| `knfsd/exports/total_read_bytes` | Total bytes read by NFS clients                      | Sum  | Bytes | 60s    |
| `knfsd/exports/total_write_bytes`| Total bytes written by NFS clients                   | Sum  | Bytes | 60s    |

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

#### Optional Metrics

| Metric Name                 | Description                                                 | Stat    | Unit    | Period |
| --------------------------- | ----------------------------------------------------------- | ------- | ------- | ------ |
| `knfsd/fscache_oldest_file` | Age of the oldest file in FS-Cache (NOT enabled by default) | Average | Seconds | 60s    |

### AWS Service Metrics

AWS-native service metrics from Amazon CloudWatch.

| Metric Name                                                 | Description                                          | Stat    | Unit                   | Period |
| ----------------------------------------------------------- | ---------------------------------------------------- | ------- | ---------------------- | ------ |
| `AWS/EC2.CPUUtilization`                                    | EC2 instance CPU utilization                         | Average | Percent                | 60s    |
| `AWS/AutoScaling.GroupDesiredCapacity`                      | Desired capacity of Auto Scaling Group               | Average | Count                  | 60s    |
| `AWS/AutoScaling.GroupInServiceInstances`                   | Number of instances in service in Auto Scaling Group | Maximum | Count                  | 60s    |
| `AWS/AutoScaling.GroupTotalInstances`                       | Total number of instances in Auto Scaling Group      | Maximum | Count                  | 60s    |
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
| `AWS/RDS.CPUCreditUsage`                                    | CPU credits consumed                                 | Average | Credits (vCPU-minutes) | 60s    |
| `AWS/RDS.CPUSurplusCreditBalance`                           | Surplus CPU credits available                        | Average | Credits (vCPU-minutes) | 60s    |
| `AWS/RDS.CPUSurplusCreditsCharged`                          | Surplus CPU credits charged                          | Average | Credits (vCPU-minutes) | 60s    |
| `AWS/RDS.WriteIOPS`                                         | Write IOPS                                           | Average | Count/Second           | 60s    |
| `AWS/RDS.ReadIOPS`                                          | Read IOPS                                            | Average | Count/Second           | 60s    |
| `AWS/RDS.NetworkTransmitThroughput`                         | Network bytes transmitted                            | Average | Bytes/Second           | 60s    |
| `AWS/RDS.NetworkReceiveThroughput`                          | Network bytes received                               | Average | Bytes/Second           | 60s    |
| `AWS/RDS.FreeableMemory`                                    | Available RAM                                        | Average | Bytes                  | 60s    |
| `AWS/RDS.SwapUsage`                                         | Swap space used                                      | Average | Bytes                  | 60s    |

## Dashboard Layout

The dashboard is organized into the following logical sections:

### Cache Overview

Overview of KNFSD caching layers including L1 (Linux filesystem cache) and L2 (FS-Cache).

| Widget                          | Metrics                                                          | Description                                                     | Stat    | Period |
| ------------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------- | ------- | ------ |
| Total READ BW                   | `knfsd/exports/total_read_bytes`                                 | Aggregate read bandwidth from clients to proxy                  | Sum     | 60s    |
| Total WRITE BW                  | `knfsd/exports/total_write_bytes`                                | Aggregate write bandwidth from clients to proxy                 | Sum     | 60s    |
| Total IOPS                      | `knfsd/exports/total_operations`                                 | Aggregate NFS operations from clients to proxy                  | Sum     | 60s    |
| Cache Hit Ratio %               | Expression: `IF(m2 > 0, (1 - (m1/m2)) * 100, 0)`                 | Percentage of reads served from cache (not fetched from source) | Sum     | 60s    |
| Cluster Size                    | `AWS/AutoScaling.GroupInServiceInstances`, `GroupTotalInstances` | Number of active and total proxy instances                      | Maximum | 60s    |
| FS-Cache Disk Used %            | `disk_used_percent` (path: `/var/cache/fscache`)                 | Percentage of FS-Cache disk space used                          | Average | 60s    |
| FS-Cache Disk Free Space        | `disk_free` (path: `/var/cache/fscache`)                         | Free space available in FS-Cache                                | Average | 60s    |
| FS-Cache Read Throughput        | `diskio_read_bytes` (nvme0n1, nvme1n1, md127)                    | Disk read throughput for cache storage                          | Sum     | 60s    |
| FS-Cache Write Throughput       | `diskio_write_bytes` (nvme0n1, nvme1n1, md127)                   | Disk write throughput for cache storage                         | Sum     | 60s    |
| NFS Inode Cache Active Objects  | `knfsd/nfs_inode_cache_active_objects`                           | Number of cached NFS inodes                                     | Average | 60s    |
| NFS Inode Cache Object Size     | `knfsd/nfs_inode_cache_objsize`                                  | Total size of NFS inode cache                                   | Average | 60s    |
| NFS Dentry Cache Active Objects | `knfsd/dentry_cache_active_objects`                              | Number of cached directory entries                              | Average | 60s    |
| NFS Dentry Cache Object Size    | `knfsd/dentry_cache_objsize`                                     | Total size of dentry cache                                      | Average | 60s    |

**Thresholds:**

* FS-Cache Disk Used: 80% (brun/frun warning), 93% (bcull/fcull critical)

### Networking Activity

Network activity for KNFSD proxy nodes showing data flow to/from clients and source filers.

| Widget                       | Metrics                               | Description                                        | Stat    | Period |
| ---------------------------- | ------------------------------------- | -------------------------------------------------- | ------- | ------ |
| Proxy Ingress Traffic        | `net_bytes_recv`                      | Total bytes received (data from on-premise/source) | Sum     | 60s    |
| Proxy Egress Traffic         | `net_bytes_sent`                      | Total bytes sent (data to NFS clients)             | Sum     | 60s    |
| Proxy NFS Client Connections | `knfsd/nfs_connections`               | Number of connected NFS clients                    | Maximum | 60s    |
| TCP/UDP Connection State     | `netstat_tcp_*`, `netstat_udp_socket` | TCP and UDP connection states                      | Average | 60s    |

### Data Transfer

Data transfer metrics showing bandwidth between different layers.

| Widget                        | Metrics                          | Description                            | Stat | Period |
| ----------------------------- | -------------------------------- | -------------------------------------- | ---- | ------ |
| Proxy to Source Bytes Read    | `knfsd/mount/read_bytes`         | Bytes read from source filer by proxy  | Sum  | 60s    |
| Proxy to Source Bytes Written | `knfsd/mount/write_bytes`        | Bytes written to source filer by proxy | Sum  | 60s    |
| Client to Proxy Bytes Read    | `knfsd/exports/total_read_bytes` | Bytes read by clients from proxy       | Sum  | 60s    |
| Client to Proxy Bytes Written | `knfsd/exports/total_write_bytes`| Bytes written by clients to proxy      | Sum  | 60s    |

### NFS Latency & Stats

Performance metrics for NFS operations between proxy and source filer.

| Widget                                | Metrics                           | Description                                                   | Stat    | Period |
| ------------------------------------- | --------------------------------- | ------------------------------------------------------------- | ------- | ------ |
| Proxy to Source Operations per Second | `knfsd/mount/operation/requests`  | NFS operations per second to source                           | Sum     | 60s    |
| Proxy to Source RPC Backlog Size      | `knfsd/nfsiostat_rpc_backlog`     | Pending RPC requests to source                                | Average | 60s    |
| Proxy to Source Read RTT              | `knfsd/nfsiostat_mount_read_rtt`  | Round trip time for read operations                           | Average | 60s    |
| Proxy to Source Write RTT             | `knfsd/nfsiostat_mount_write_rtt` | Round trip time for write operations                          | Average | 60s    |
| Proxy to Source Read EXE              | `knfsd/nfsiostat_mount_read_exe`  | Execution time for read operations (RTT + kernel processing)  | Average | 60s    |
| Proxy to Source Write EXE             | `knfsd/nfsiostat_mount_write_exe` | Execution time for write operations (RTT + kernel processing) | Average | 60s    |

**Note:** RTT = Round Trip Time (network time), EXE = Execution Time (RTT + kernel processing time)

### NFS Operations

Detailed breakdown of NFS operations by operation type (GETATTR, READ, WRITE, etc.).

| Widget                  | Metrics                                               | Description                                    | Stat | Period |
| ----------------------- | ----------------------------------------------------- | ---------------------------------------------- | ---- | ------ |
| NFS Ops: Sent Bytes     | `knfsd/mount/operation/sent_bytes` (by operation)     | Bytes sent for each NFS operation type         | Sum  | 60s    |
| NFS Ops: Received Bytes | `knfsd/mount/operation/received_bytes` (by operation) | Bytes received for each NFS operation type     | Sum  | 60s    |
| NFS Ops: Requests       | `knfsd/mount/operation/requests` (by operation)       | Number of requests for each NFS operation type | Sum  | 60s    |
| NFS Ops: Major Timeouts | `knfsd/mount/operation/major_timeouts` (by operation) | Major timeouts for each NFS operation type     | Sum  | 60s    |
| NFS Ops: Errors         | `knfsd/mount/operation/errors` (by operation)         | Errors for each NFS operation type             | Sum  | 60s    |

**Supported Operations:** NULL, GETATTR, SETATTR, LOOKUP, ACCESS, READLINK, READ, WRITE, CREATE, MKDIR, SYMLINK, MKNOD, REMOVE, RMDIR, RENAME, LINK, READDIR, READDIRPLUS, FSSTAT, FSINFO, PATHCONF, COMMIT

### Disk IO Performance

Performance statistics for NVMe or EBS volumes used for `/var/cache/fscache`.

| Widget                        | Metrics                                   | Description                                    | Stat | Period |
| ----------------------------- | ----------------------------------------- | ---------------------------------------------- | ---- | ------ |
| Completed Operations          | `diskio_reads`, `diskio_writes`           | Number of completed read/write operations      | Sum  | 60s    |
| Bytes Transferred             | `diskio_read_bytes`, `diskio_write_bytes` | Total bytes read/written                       | Sum  | 60s    |
| I/O Requests Queued           | `diskio_io_time`                          | Time I/O requests spent queued                 | Sum  | 60s    |
| Instance Performance Exceeded | `diskio_*_performance_exceeded_*`         | Time instance performance limits were exceeded | Sum  | 60s    |
| Volume Queue Length           | `diskio_*_volume_queue_length`            | Number of operations queued at volume level    | Sum  | 60s    |

### EC2 Node Performance

General EC2 instance performance metrics.

| Widget                       | Metrics                                 | Description                                    | Stat    | Period |
| ---------------------------- | --------------------------------------- | ---------------------------------------------- | ------- | ------ |
| CPU Utilization              | `AWS/EC2.CPUUtilization`                | EC2 instance CPU utilization                   | Average | 60s    |
| CPU Usage                    | `cpu_usage_active`, `cpu_usage_iowait`  | Detailed CPU usage breakdown                   | Average | 60s    |
| Memory/Swap Utilization      | `mem_used_percent`, `swap_used_percent` | Memory and swap usage                          | Average | 60s    |
| Memory Metrics               | `mem_buffered`, `mem_cached`            | Memory used for buffers and cache              | Average | 60s    |
| Network I/O                  | `net_drop_*`, `net_err_*`               | Network packet drops and errors                | Sum     | 60s    |
| ENA Performance              | `ethtool_*_allowance_exceeded`          | Packets queued/dropped due to allowance limits | Sum     | 60s    |
| Operating System Disk Used % | `disk_used_percent` (path: `/`)         | Root filesystem disk usage                     | Average | 60s    |
| Processes                    | `processes_*`                           | Process and thread statistics                  | Average | 60s    |

**Thresholds:**

* CPU Utilization: 80% (warning)
* Memory Utilization: 80% (warning)

### FSID Performance

KNFSD FSID daemon performance metrics for filesystem ID management.

| Widget             | Metrics                         | Description                                     | Stat    | Period |
| ------------------ | ------------------------------- | ----------------------------------------------- | ------- | ------ |
| Operation Count    | `knfsd/fsid/operation/count`    | Number of FSID operations by command and result | Sum     | 60s    |
| Operation Duration | `knfsd/fsid/operation/duration` | Duration of FSID operations                     | Average | 60s    |
| SQL Query Count    | `knfsd/fsid/sql/query/count`    | Number of SQL queries executed                  | Sum     | 60s    |
| SQL Query Duration | `knfsd/fsid/sql/query/duration` | Duration of SQL queries                         | Average | 60s    |
| Request Count      | `knfsd/fsid/request/count`      | Number of requests received                     | Sum     | 60s    |
| Request Duration   | `knfsd/fsid/request/duration`   | Total duration of requests including retries    | Average | 60s    |
| Request Retries    | `knfsd/fsid/request/retries`    | Number of request retries                       | Sum     | 60s    |

**Commands:** `get_fsidnum`, `get_or_create_fsidnum`, `get_path`
**SQL Queries:** `get_fsid`, `allocate_fsid`, `get_path`
**Results:** `ok`, `not_found`, `retry`

### RDS Database Performance

PostgreSQL RDS performance metrics for the FSID database.

| Widget                       | Metrics                                                         | Description                                 | Stat    | Period |
| ---------------------------- | --------------------------------------------------------------- | ------------------------------------------- | ------- | ------ |
| DB Load                      | `AWS/RDS.DBLoad`, `DBLoadCPU`, `DBLoadNonCPU`                   | Database active sessions                    | Average | 60s    |
| DB Connections               | `AWS/RDS.DatabaseConnections`                                   | Number of database connections              | Average | 60s    |
| DB IAM Auth                  | `AWS/RDS.IamDbAuth*`                                            | IAM authentication requests and results     | Sum     | 60s    |
| DB CPU Utilization           | `AWS/RDS.CPUUtilization`                                        | RDS instance CPU utilization                | Average | 60s    |
| DB EC2 CPU Credits           | `AWS/RDS.CPUCreditUsage`                                        | CPU credits consumed                        | Average | 60s    |
| DB EC2 CPU Unlimited Credits | `AWS/RDS.CPUSurplus*`                                           | Surplus CPU credits for unlimited mode      | Average | 60s    |
| DB IOPS                      | `AWS/RDS.ReadIOPS`, `WriteIOPS`                                 | Read and write IOPS                         | Average | 60s    |
| DB Network Throughput        | `AWS/RDS.NetworkTransmitThroughput`, `NetworkReceiveThroughput` | Network throughput                          | Average | 60s    |
| DB Memory                    | `AWS/RDS.FreeableMemory`, `SwapUsage`                           | Available memory and swap usage             | Average | 60s    |

**Thresholds:**

* CPU Credits: 70% (warning), 90% (critical)
* Surplus Credits: 10+ (warning for additional charges)
