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

| Metric Name                              | Description                                                                                                     |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **knfsd/nfs_connections**                | The number of NFS clients connected to the KNFSD proxy (used for autoscaling).                                  |
| **knfsd/nfs_inode_cache_active_objects** | The number of active objects in the Linux NFS inode cache.                                                      |
| **knfsd/dentry_cache_active_objects**    | The number of active objects in the Linux dentry cache.                                                         |
| **knfsd/nfs_inode_cache_objsize**        | The total size of the objects in the Linux NFS inode cache in bytes.                                            |
| **knfsd/dentry_cache_objsize**           | The total size of the objects in the Linux dentry cache in bytes.                                               |
| **knfsd/nfsiostat_mount_read_exe**       | The average read operation EXE per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).          |
| **knfsd/nfsiostat_mount_read_rtt**       | The average read operation RTT per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).          |
| **knfsd/nfsiostat_mount_write_exe**      | The average write operation EXE per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).         |
| **knfsd/nfsiostat_mount_write_rtt**      | The average write operation RTT per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).         |
| **knfsd/nfsiostat_ops_per_second**       | The number of NFS operations per second per NFS client mount over the past 60 seconds (KNFSD --> Source Filer). |
| **knfsd/nfsiostat_rpc_backlog**          | The RPC backlog per NFS client mount over the past 60 seconds (KNFSD --> Source Filer).                         |
| **knfsd/mount/read_bytes**               | The total number of bytes read from the source NFS server.                                                      |
| **knfsd/mount/write_bytes**              | The total number of bytes written to the source NFS server.                                                     |
| **knfsd/mount/operation/requests**       | The total number of NFS requests sent to the source NFS server.                                                 |
| **knfsd/mount/operation/sent_bytes**     | The total number of bytes sent to the source NFS server. This includes the RPC protocol headers.                |
| **knfsd/mount/operation/received_bytes** | The total number of bytes received from the source NFS server. This includes the RPC protocol headers.          |
| **knfsd/mount/operation/major_timeouts** | The total number of RPC major timeouts (`timeo`, default 60 seconds) between the proxy and source NFS servers.  |
| **knfsd/mount/operation/errors**         | The total number of RPC errors between the proxy and the source NFS servers.                                    |
| **knfsd/exports/total_operations**       | The total number of NFS operations received from NFS clients.                                                   |
| **knfsd/exports/total_read_bytes**       | The total number of bytes read by NFS clients.                                                                  |
| **knfsd/exports/total_write_bytes**      | The total number of bytes written by NFS clients.                                                               |
| **knfsd/fscache_oldest_file**            | The age of the oldest file in FS-Cache. This metric is not enabled by default.                                  |

## Dashboards

The KNFSD Metrics Dashboard is created automatically by the metrics initialisation Terraform that is detailed in the [Metrics Prerequisites](#metrics-prerequisites).

Once ran, you can then access the dashboard from [https://console.aws.amazon.com/cloudwatch](https://console.aws.amazon.com/cloudwatch/home#dashboards/).

## Custom Configuration

The metrics can be configured using the `METRICS_AGENT_CONFIG` variable in the Terraform module, or by customizing the metrics config when building the image.

Configuring the metrics using Terraform is the simplest option. You can provide the metrics configuration using a file or directly inline using heredoc.

Providing the metrics config from a file:

```terraform
module "nfs_proxy" {
  source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.9"

  METRICS_AGENT_CONFIG = file("metrics-config.yaml")
}
```

Providing the metrics config inline using heredoc syntax:

```terraform
module "nfs_proxy" {
  source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.9"

  METRICS_AGENT_CONFIG = <<- EOT
    receivers:
      mounts:
        collection_interval: 5m
  EOT
}
```

See the [knfsd-metrics-agent README](../../image/resources/knfsd-metrics-agent/README.md) for details on how to configure the metrics agent.
