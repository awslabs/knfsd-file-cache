# KNFSD Deployment

This directory contains a [Terraform Module](https://www.terraform.io/docs/modules/index.html) for deploying KNFSD on Amazon Web Services.

The `main` branch may be updated at any time with the latest changes which could be breaking. You should always configure your module to use a release. This can be configured in the modules Terraform Configuration block, referencing a git tag in the repository.

```bash
source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.11"
```

## Prerequisites

Before continuing with the deployment and configuration of KNFSD you should review the deployment [prerequisites](docs/prerequisites.md).

## Features

There are a number of optional features that can be enabled and configured for KNFSD. If you are planning on using any of these features then please review the appropriate documentation section.

* [Metrics](docs/metrics.md) - System and proxy metrics for monitoring and observing KNFSD
* [Autoscaling](docs/autoscaling.md) - Automatic scale up of KNFSD in response to the number of connected NFS clients
* [Agent](../image/resources/knfsd-agent/README.md) - A lightweight HTTP API that provides information on KNFSD nodes
* [Fanout Architecture](docs/fanout.md) - Documentation on how to deploy KNFSD in the fanout (2-tier) architecture

## Quick Deploy

```sh
cd knfsd-file-cache/deployment/terraform-module-knfsd
terraform init
terraform apply
```

## Usage

To integrate the KNFSD module into your own Terraform project, you should create a `deploy.tf` file in a separate directory outside of the KNFSD repository structure and add the following:

> NOTE: The order of [precedence](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration) will be used to determine the AWS Region to use for the deployment.

```terraform
# add a provider block if you wish to explicitly configure the AWS Region
provider "aws" {
  region = "us-east-1"
}

module "nfs_proxy" {
  source         = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.11"
  SUBNET         = "subnet-0123456789abcdefg"
  TRAFFIC_MODE   = "dns_round_robin"
  PROXY_AMI      = "ami-0123456789abcdefg"
  EXPORT_MAP     = "10.0.5.5;/remoteexport;/remoteexport"
  KNFSD_NODES    = 1
}

# Print the DNS name of KNFSD proxy
output "dns_name" {
  value = module.nfs_proxy.dns_name
}
```

Edit the [configuration variables](#configuration-variables) to match your desired configuration.

## Non-default VPC and Private Subnet Deployment

This above usage assumes you are using the **default** VPC. If you are using a **non-default** VPC, please make sure to review the [FSID Database Options](#fsid-database-options) section below as `FSID_DB_SUBNET_GROUP_NAME` is required when using a non-default VPC.

When deploying KNFSD File Cache in private subnets without internet connectivity, VPC endpoints are required for AWS service access. See [VPC Endpoints](docs/vpc-endpoints.md) for detailed setup instructions.

  > NOTE: The VPC endpoints must be created or already exist **before** deploying KNFSD modules.

## Configuration Variables

### AWS Configuration

| Variable | Description                                                                                                                                      | Required | Default |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| `SUBNET` | The [AWS Subnet](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html) to use for deployment of available zone resources.           | True     |         |

### Network Configuration

| Variable                | Description                                                                                                                                                                                                                                                                                                                                             | Required | Default                                           |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------- |
| `TRAFFIC_MODE`          | The [client traffic distribution mode](docs/traffic-distribution.md) used to distribute traffic between proxy instances in the KNFSD proxy cluster. Can be either `dns_round_robin`, `loadbalancer`, or `none`. The recommended option is `dns_round_robin`. If using `none` you will need to provide your own solution to handle traffic distribution. | True     |                                                   |
| `LOADBALANCER_IP`       | The static private IPv4 address to use for the Network Load Balancer when `TRAFFIC_MODE = "loadbalancer"`. If not specified, a random IP address will be assigned from the VPC Subnet.                                                                                                                                                                  | False    | `null`                                            |
| `DNS_NAME`              | The fully qualified DNS name (FQDN) to use for the KNFSD proxy cluster. Defaults to: `"lb-knfsd/knfsd.nfsproxy-a1b2c3d4.aws.internal."` [Note: the trailing period is required].                                                                                                                                                                        | False    | `"lb-knfsd/knfsd.{PROXY_BASENAME}.aws.internal."` |
| `ASG_EGRESS_CIDR_BLOCK` | The IPv4 CIDR block to use for the Auto Scaling Group (ASG) EGRESS rule for KNFSD proxy instances. Default: `0.0.0.0/0`.                                                                                                                                                                                                                                | False    | `0.0.0.0/0`                                       |
| `NFS_PORTS`             | The list of NFS ports (TCP & UDP) to create security group INGRESS rules for the KNFSD proxy instances in the Auto Scaling Group (ASG)/Network Load Balancer (NLB). Default: see `map(object({port = number, check_port = number, name = string}))` in `variables.tf`.                                                                                  | False    | see `variables.tf` for TCP/UDP ports              |

### Health Check Configuration

| Variable                            | Description                                                                                                                                                                                                                             | Required | Default |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------- |
| `HEALTHCHECK_INITIAL_DELAY_SECONDS` | Initial delay before a failing health check will replace an proxy instance. This allows the proxy time to start up. Note, this only applies to the initial boot. If you reboot a proxy instance this initial interval *does not* apply. | False    | `600`   |
| `HEALTHCHECK_INTERVAL_SECONDS`      | How frequently (in seconds) to probe if a proxy instance is healthy. This is measured from the start of one probe, to the start of the next probe.                                                                                      | False    | `60`    |
| `HEALTHCHECK_TIMEOUT_SECONDS`       | How long (in seconds) to wait for a response from a probe. Must be less than or equal to `HEALTHCHECK_INTERVAL_SECONDS`.                                                                                                                | False    | `5`     |
| `HEALTHCHECK_HEALTHY_THRESHOLD`     | Number of sequential successful probe results for a proxy instance to be considered healthy.                                                                                                                                            | False    | `3`     |
| `HEALTHCHECK_UNHEALTHY_THRESHOLD`   | Number of sequential failed probe results for a proxy instance to be considered unhealthy.                                                                                                                                              | False    | `3`     |

**NOTE:** `HEALTHCHECK_INITIAL_DELAY_SECONDS` only applies to the first time the proxy starts up. If you reboot the proxy the standard health checks intervals will apply. The time allowed for a reboot is `HEALTHCHECK_INTERVAL_SECONDS * (HEALTHCHECK_UNHEALTHY_THRESHOLD - 1) + HEALTHCHECK_TIMEOUT_SECONDS`, with the default values this is `60 seconds * (3 probes - 1) + 2 seconds = 122 seconds` (effectively 2 minutes).

Increasing `HEALTHCHECK_INTERVAL_SECONDS` and/or `HEALTHCHECK_UNHEALTHY_THRESHOLD` will allow more time to reboot a proxy instance. However, it will also delay the system from detecting unhealthy instances.

### Export Configuration

| Variable                  | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Required                                                                             | Default |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------- |
| `EXPORT_MAP`              | A list of NFS Exports to mount from source filer and re-export in the format `<SOURCE_IP/DNS>;<SOURCE_EXPORT>;<TARGET_EXPORT>`.<br><br> For example to mount `10.100.100.1/export` from source filer and re-export as `10.100.100.1/reexport` you would set the `EXPORT_MAP` variable to `10.100.100.1;/export;/reexport`.<br><br>You can specify multiple re-exports using a comma, for example `10.100.100.1;/assets;/assetscache,10.100.100.1;/textures;/texturescache`. An <optional> 4th field can be used to override the filesystem type of the mount, for example `10.100.100.1;/export;/reexport;efs`.  | `EXPORT_MAP`, `EXPORT_HOST_AUTO_DETECT` or NetApp Auto-Discovery must be configured. | N/A     |
| `EXPORT_HOST_AUTO_DETECT` | A list of IP addresses or hostnames of NFS filers that respond to the `showmount` command. KNFSD will automatically detect and re-export mounts from this filer. Exports paths on the cache will match the export path on the source filer.<br><br> You can specify multiple filers using a comma, for example `10.100.100.1,10.100.200.1` however you must ensure that these hosts are not exporting the same exports.                                                                                                                                                                                          | `EXPORT_MAP`, `EXPORT_HOST_AUTO_DETECT` or NetApp Auto-Discovery must be configured. | N/A     |
| `EXCLUDED_EXPORTS`        | A list of filter patterns to be excluded from auto-discovery (see [Filter Patterns](docs/filter-patterns.md)). Auto-discovery will ignore any exports that match any of the exclude patterns. Does not apply to mounts specified in the `EXPORT_MAP`. Paths filtered from auto-discovery can be explicitly exported using `EXPORT_MAP`, this can be used to change the export path.                                                                                                                                                                                                                              | False                                                                                | `[]`    |
| `INCLUDED_EXPORTS`        | If set, auto-discovery will only include paths matching a filter pattern from the include list (see [Filter Patterns](docs/filter-patterns.md)). Does not apply to mounts specified in the `EXPORT_MAP`. Paths filtered from auto-discovery can be explicitly exported using `EXPORT_MAP`, this can be used to change the export path.                                                                                                                                                                                                                                                                           | False                                                                                | `[]`    |

### NetApp Exports Auto-Discovery Configuration

If using the NetApp Exports Auto-Discovery feature, please also read the [NetApp Exports](docs/netapp-exports.md) and [NetApp ShowMount Tool](../image/resources/netapp-exports/README.md) docs.

| Variable                    | Description                                                                                                                                                                                                                                                                           | Required                                 | Default                               |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------- |
| `ENABLE_NETAPP_AUTO_DETECT` | Enables automatic discovery of exports using the NetApp REST API.                                                                                                                                                                                                                     | False                                    | `false`                               |
| `NETAPP_HOST`               | DNS or IP of the NetApp server. This is the DNS or IP name clients use when mounting the NFS shares.                                                                                                                                                                                  | If `ENABLE_NETAPP_AUTO_DETECT` is `true` | `""`                                  |
| `NETAPP_URL`                | URL of the NetApp REST API. This *must* include the API version and end with a slash, for example `https://netapp.example/api/v1/`.                                                                                                                                                   | If `ENABLE_NETAPP_AUTO_DETECT` is `true` | `""`                                  |
| `NETAPP_USER`               | The username used to authenticate with the NetApp REST API.                                                                                                                                                                                                                           | If `ENABLE_NETAPP_AUTO_DETECT` is `true` | `""`                                  |
| `NETAPP_SECRET`             | The name of an AWS Secrets Manager 'Secret' containing the NetApp REST API password.                                                                                                                                                                                                  | If `ENABLE_NETAPP_AUTO_DETECT` is `true` | `""`                                  |
| `NETAPP_SECRET_REGION`      | The AWS Region where AWS Secrets Manager is storing the NetApp password.                                                                                                                                                                                                              | False                                    |  AWS region that knfsd is running in  |
| `NETAPP_SECRET_VERSION`     | The version of the AWS Secrets Manager 'Secret'.                                                                                                                                                                                                                                      | False                                    | `AWSCURRENT`                          |
| `NETAPP_CA`                 | PEM encoded certificate containing the root certificate for the NetApp REST API. This can also include intermediate certificates to provide the full certificate chain. To read this from a file use the [Terraform file function](https://www.terraform.io/language/functions/file). | If `ENABLE_NETAPP_AUTO_DETECT` is `true` | `""`                                  |
| `NETAPP_ALLOW_COMMON_NAME`  | Allows using the Common Name (CN) field of the certificate as a DNS name when the certificate does not include a Subject Alternate Name (SAN) field.                                                                                                                                  | False                                    | `false`                               |

### KNFSD Proxy Configuration

| Variable                           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Required | Default                         |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------- |
| `PROXY_BASENAME`                   | Prefix used to name AWS resources. Every deployment in an AWS account *MUST* be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account).                                                                                                                                                                                                                                             | False    | `nfsproxy`                      |
| `EXPORT_CIDR`                      | The CIDR to use in `/etc/exports` of the KNFSD proxy for filesystem re-export (VPC CIDR of `SUBNET` is used if not specified).                                                                                                                                                                                                                                                                                                                                 | False    | `""`                            |
| `PROXY_AMI`                        | The AMI ID of the KNFSD image, built by Packer.                                                                                                                                                                                                                                                                                                                                                                                                                | True     | N/A                             |
| `KEY_NAME`                         | The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM.                                                                                                                                                                                                                                                                                                                                                                           | False    | `""`                            |
| `KNFSD_NODES`                      | The number of KNFSD instances to deploy as part of the cluster.                                                                                                                                                                                                                                                                                                                                                                                                | False    | `1`                             |
| `RESERVE_KNFSD_CAPACITY`           | Create an EC2 Capacity Reservation for the cluster. The KNFSD nodes are often large instances with lots of local NVMe storage. This means they can sometimes be difficult to schedule which can cause delays when replacing unhealthy instances.<br><br>A reservation ensures that the capacity for the KNFSD cluster is always available in AWS, regardless of the state of the instances. A reservation is not a commitment, and can be deleted at any time. | False    | `false`                         |
| `TAGS`                             | AWS TAGS to apply to all KNFSD proxy EC2 instances.                                                                                                                                                                                                                                                                                                                                                                                                            | False    | `{}`                            |
| `VFS_CACHE_PRESSURE`               | The value to set for `vfs_cache_pressure` rule.                                                                                                                                                                                                                                                                                                                                                                                                                | False    | `100`                           |
| `READ_AHEAD`                       | The number of bytes to read ahead. Must be a multiple of the kernel page size (8 KiB for 5.11). The kernel will round this down to the nearest page.                                                                                                                                                                                                                                                                                                           | False    | `8388608`                       |
| `ENABLE_METRICS`                   | Enable the Amazon CloudWatch Logs & EC2 Metrics and KNFSD Metrics (Open-Telemetry) Agents.                                                                                                                                                                                                                                                                                                                                                                     | False    | `true`                          |
| `METRICS_AGENT_CONFIG`             | Custom YAML configuration for the metrics agent. The configuration *is not* validated by Terraform when using a custom config, please check the proxy startup log. See the custom configuration section in the [metrics documentation](docs/metrics.md) for more details.                                                                                                                                                                                      | False    | `""`                            |
| `CUSTOM_PRE_STARTUP_SCRIPT`        | Optional bash script to run BEFORE the [proxy-startup.sh](terraform-module-knfsd/resources/proxy-startup.sh) script. For example `file("/home/ben/myscript.sh")`.                                                                                                                                                                                                                                                                                              | False    | empty script                    |
| `CUSTOM_POST_STARTUP_SCRIPT`       | Optional bash script to run AFTER the [proxy-startup.sh](terraform-module-knfsd/resources/proxy-startup.sh) script. For example `file("/home/ben/myscript.sh")`.                                                                                                                                                                                                                                                                                               | False    | empty script                    |
| `INSTANCE_TYPE`                    | The AWS EC2 instance type to use for the KNFSD cache.                                                                                                                                                                                                                                                                                                                                                                                                          | False    | `i3en.6xlarge`                  |
| `ROOT_DISK_SIZE`                   | The size of the root disk in GB.                                                                                                                                                                                                                                                                                                                                                                                                                               | False    | `20`                            |
| `ENABLE_KNFSD_AGENT`               | Enable the [KNFSD HTTP Agent](../image/resources/knfsd-agent/README.md).                                                                                                                                                                                                                                                                                                                                                                                       | False    | `true`                          |
| `ENABLE_STATUS_CHECK`              | Whether to enable the status check that waits for all EC2 instances to be KNFSD status: `ready` during Terraform deployment. Must be `true` for `fanout` deployments.                                                                                                                                                                                                                                                                                          | False    | `false`                         |

### Cachefilesd Configuration

| Variable                     | Description                                                                                                                                                                                                     | Required | Default      |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------ |
| `CACHEFILESD_DISK_TYPE`      | The disk type to use for the cachefiles directory. Can be either `local-nvme`, `ebs-gp3` or `ebs-io2`. Local ephemeral NVMe provides the highest performance, whilst EBS can provide data persistence.          | False    | `local-nvme` |
| `CACHEFILESD_EBS_COUNT`      | (Only used if `CACHEFILESD_DISK_TYPE` = `ebs-gp3` or `ebs-io2`), the number of EBS volumes to create for cachefilesd (1-8). If >1, then RAID 0 array is created.                                                | False    | `1`          |
| `CACHEFILESD_EBS_SIZE`       | (Only used if `CACHEFILESD_DISK_TYPE` = `ebs-gp3` or `ebs-io2`), the size of the EBS volume in GB. `ebs-gp3` supports 1 GiB - 65536 GiB (64 TiB), `ebs-io2` supports 4 GiB - 65536 GiB (64 TiB).                | False    | `1024`       |
| `CACHEFILESD_EBS_IOPS`       | (Only used if `CACHEFILESD_DISK_TYPE` = `ebs-gp3` or `ebs-io2`), the number of I/O operations per second (IOPS) for the EBS volume. `ebs-gp3` supports 3000 - 80000 IOPS, `ebs-io2` supports 100 - 256000 IOPS. | False    | `3000`       |
| `CACHEFILESD_EBS_THROUGHPUT` | (Only used if `CACHEFILESD_DISK_TYPE` = `ebs-gp3`), the throughput (MB/s) for the EBS volume. `ebs-gp3` supports 125 - 2000 MiB/s.                                                                              | False    | `125`        |

### Mount Options

These mount options are for the proxy to the source server.

| Variable            | Description                                                                                                                                                                                                                            | Required | Default   |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------- |
| `NCONNECT`          | The number of TCP connections to use when connecting to the source.                                                                                                                                                                    | False    | `16`      |
| `ACREGMIN`          | The minimum time (in seconds) that the NFS client caches attributes of a regular file.                                                                                                                                                 | False    | `600`     |
| `ACREGMAX`          | The maximum time (in seconds) that the NFS client caches attributes of a regular file.                                                                                                                                                 | False    | `600`     |
| `ACDIRMIN`          | The minimum time (in seconds) that the NFS client caches attributes of a directory.                                                                                                                                                    | False    | `600`     |
| `ACDIRMAX`          | The maximum time (in seconds) that the NFS client caches attributes of a directory. This can be reduced to improve the cache coherency for `readdir` operationns (e.g `ls`) at the cost of increasing metadata requests to the source. | False    | `600`     |
| `RSIZE`             | The maximum number of bytes the proxy will read from the source in a single request. The actual value will be negotiated with the source server to determine the maximum value support by both machines.                               | False    | `1048576` |
| `WSIZE`             | The maximum number of bytes the proxy will write to the source in a single request. The actual value will be negotiated with the source server to determine the maximum value support by both machines.                                | False    | `1048576` |
| `MOUNT_OPTIONS`     | Any additional NFS mount options not covered by existing variables. These options will be applied to all NFS mounts.                                                                                                                   | False    | `""`      |
| `NFS_MOUNT_VERSION` | The mount version to use for NFS client mounts (`vers` option). Acceptable values are `3`, `4`, `4.0`, `4.1`, `4.2`.                                                                                                                   | False    | `3`       |

### NFS Kernel Server Options

| Variable                | Description                                                                                                                                                                                                                                                                                                                                           | Required | Default       |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------- |
| `DISABLED_NFS_VERSIONS` | The versions of NFS that should be disabled in `nfs-kernel-server`. Explicitly disabling unwanted NFS versions prevents clients from accidentally auto-negotiating an undesired NFS version. Specify multiple versions to disable with a comma separated list. Acceptable values are `3`, `4`, `4.0`, `4.1`, `4.2`. NFS Version 2 is always disabled. | False    | `4.0,4.1,4.2` |
| `NUM_NFS_THREADS`       | The number of NFS Threads to use for KNFSD.                                                                                                                                                                                                                                                                                                           | False    | `512`         |

**NOTE:** When using NFS v4, it is recommended that you use NFS v4.1 or greater. NFS v4.1 has many improvements to fix limitations of the NFS v4.0 protocol.

### Export Options

| Variable         | Description                                                                                                                                | Required | Default |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| `NOHIDE`         | When `true`, adds the `nohide` option to all the exports. Overridden by `AUTO_REEXPORT`                                                    | False    | `true`  |
| `AUTO_REEXPORT`  | When `true` enables the `crossmnt` option on all exports and automatically re-exports any nested mounts that were not explicitly exported. | False    | `false` |
| `EXPORT_OPTIONS` | Any custom NFS exports options. These options will be applied to all NFS exports.                                                          | False    | `""`    |

Use of `AUTO_REEXPORT` requires that `FSID_MODE` is `local` or `external`. `external` is recommended. See [Auto Re-export](docs/auto-re-export.md) for more detail.

### FSID Database Options

| Variable                    | Description                                                                                                               | Required | Default      |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------- | -------- | ------------ |
| `FSID_MODE`                 | How to assign FSIDs (File System Identifiers) to each export. The options are `static`, `local`, or `external`.           | False    | `"external"` |
| `FSID_DATABASE_DEPLOY`      | Set to `false` to prevent automatically creating an Amazon RDS PostgreSQL instance when `FSID_MODE` is set to `external`. | False    | `true`       |
| `FSID_DATABASE_CONFIG`      | Allows overriding the default FSID database configuration when `FSID_MODE` is set to `external`.                          | False    | `{}`         |
| `FSID_DB_SUBNET_GROUP_NAME` | The name of the Amazon RDS DB subnet group to use for the FSID database. Required when using a non-default VPC.           | False    | `null`       |
| `FSID_DATABASE_IAM_POLICY`  | Allows overriding the default FSID database IAM policy when `FSID_MODE` is set to `external` with custom IAM policy ARN.  | False    | `""`         |

The recommended `FSID_MODE` is to always use `external`. For more details on `FSID_MODE` and `FSID_DATABASE_CONFIG` see [Filesystem Identifiers](docs/fsids.md).

The `FSID_MODE` option supports:

* `static` - Each export is explicitly allocated an incrementing FSID number on start-up. This requires all the exports to be known at start-up and is not compatible with `AUTO_REEXPORT=true`. `static` is only recommended if using an explicit `EXPORT_MAP`.

* `local` - Each export is automatically allocated an FSID number by `mountd` using the standard NFS `fsidd` service. This uses a local sqlite database to store FSID mappings. This is not recommended for production and should only be used for single instance proxy clusters.

  If multiple proxy instances in a cluster allocate a different FSID to the same export then I/O errors or data corruption may occur if a client changes instance.

* `external` - Each export is automatically allocated an FSID number by `mountd` using the `knfsd-fsidd` service. This uses an Amazon RDS PostgreSQL instance to store the FSID mappings. This ensures that all the instances in the cluster allocate the same FSID to each export.

**NOTE:** When deploying a database; a default VPC will cause Terraform to automatically generate a `default` DB subnet group, containing at least 2 subnets, each in a different availability zone. If you are using a non-default VPC for the database, you should create a DB subnet group in RDS, containing at least 2 subnets, each in a different availability zone, and then specify `FSID_DB_SUBNET_GROUP_NAME`. The single AZ deployment of the database will still target the availability zone of the provided subnet via `var.SUBNET`. The RDS DB subnet group must contain the subnet defined in `var.SUBNET`.

**INFO:** AWS mandates that the DB subnet group must contain at least 2 subnets, each in a different availability zone, just in case you want to convert the database to a multi-AZ deployment in the future or in the case of AZ failure, you will have the ability to failover manually to another AZ.

### Autoscaling Configuration

| Variable                                      | Description                                                                                                                            | Required | Default |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------- |
| `ENABLE_KNFSD_AUTOSCALING`                    | Should autoscaling be enabled for KNFSD? **You MUST set the `ENABLE_METRICS` variable to `true` if enabling autoscaling**.             | False    | `false` |
| `KNFSD_AUTOSCALING_NFS_CONNECTIONS_THRESHOLD` | The number of NFS client connections to KNFSD that should be targeted for each instance (exceeding will trigger a scale-up).           | False    | `250`   |
| `KNFSD_AUTOSCALING_MIN_INSTANCES`             | The minimum number of KNFSD instances to set regardless of the traffic volumes.                                                        | False    | `1`     |
| `KNFSD_AUTOSCALING_MAX_INSTANCES`             | The maximum number of KNFSD instances to set regardless of the traffic volumes.                                                        | False    | `10`    |

### CI/CD Configuration

| Variable          | Description                                                                                                                                                                                                                                                                                                       | Required | Default |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------- |
| `ASSUME_ROLE_ARN` | The ARN of the IAM role to assume for AWS CLI commands in local-exec provisioners for CI/CD pipelines. If not provided, no role assumption will be performed and the local-exec provisioner will use the existing AWS credentials from the environment. Example: `arn:aws:iam::123456789012:role/DeploymentRole`. | False    | `null`  |

## Deploy KNFSD

Once you have created your `deploy.tf`, you can deploy KNFSD with:

```sh
terraform init
terraform apply
```

## Outputs

| Output                                | Description                                                                                                                                 |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `autoscaling_group_name`              | Name of the KNFSD proxy Auto Scaling Group.                                                                                                 |
| `autoscaling_group_security_group_id` | Security Group ID for the KNFSD proxy Auto Scaling Group.                                                                                   |
| `dns_name`                            | The private DNS name of the KNFSD Network Load Balancer or Auto Scaling Group (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`). |
| `nfsproxy_loadbalancer_dnsaddress`    | The private DNS address of the Network Load Balancer (when `TRAFFIC_MODE = "loadbalancer"`).                                                |
| `nfsproxy_loadbalancer_ipaddress`     | The private IP address of the Network Load Balancer (when `TRAFFIC_MODE = "loadbalancer"`).                                                 |
| `nfsproxy_security_group_id`          | Security Group ID for the NFS clients to connect to the KNFSD proxy instances (when `TRAFFIC_MODE` is `dns_round_robin` or `loadbalancer`). |
| `database_config`                     | Database configuration for deployed RDS PostgreSQL database. Only available when database is deployed by this module.                       |
| `database_iam_policy`                 | The ARN of the IAM policy for `rds-db:connect` database access. Only available when database is deployed by this module.                    |
| `cluster_ready`                       | Boolean indicating if all KNFSD instances are ready and fully operational. Use this as a dependency for downstream resources.               |

## Caveats

### Excluding nested mounts

If you exclude a nested mount but still export the parent mount you may get I/O errors when accessing the nested mount.

The exact behaviour will depend on how the source server has exported the nested mount.

If the source server exports the mount with the `crossmnt`, or `nohide` options then trying to access the nested mount, or list the directory containing the nested mount will result in I/O errors.

If the source server exports the mount without `crossmnt`, or `hide` options then the directory for the nested mount will be visible, but empty.

It is advised that if you exclude a nested mount, you also exclude the parent mount. You may however exclude a parent mount but include a nested mount.

For example, if you have the following mounts:

```text
/assets
/assets/common
/assets/common/textures
```

You could exclude `/assets`, but still export `/assets/common` and `/assets/common/textures`. You could also export only `/assets/common/textures`.

However, exporting `/assets` but excluding `/assets/common` could cause errors.

Exporting `/assets` and `/assets/common/textures`, but excluding `/assets/common` will likely fail, and can have unintended side-effects as the proxy will try to create the directory `/assets/common`.

### Combining auto-discovery and explicit mounts

While auto-discovery and explicit mounts can be combined the system does not have any special handling for duplicate paths.

As such it is not recommended to combine multiple auto-discovery methods, or explicit (`EXPORT_MAP`).

The behaviour of duplicates is undefined. The system might overwrite one mount with another, or it may error.

### Limitations on export names

The proxy cannot re-export any path that matches a symlink on the local server.

The most likely symlinks that will cause conflicts are:

* `/bin`
* `/lib`
* `/lib32`
* `/lib64`
* `/libx32`
* `/sbin`

The proxy will fail to start if it attempts to export a path that matches a symlink. Check the logs for errors such as:

```text
ERROR: Cannot mount 10.0.0.2:/bin because /bin matches a symlink
```

If you are providing a manual export list, specify a different path for the export, such as `10.0.0.2;/bin;/binaries`.

If you're using auto-discovery add the path to the list of excluded exports, for example `EXCLUDED_EXPORTS = ["/bin"]`

For a full list of symlinks, start an EC2 instance using the KNFSD proxy AMI (without the standard startup script) and run the command:

```bash
find / -type l
```

Most of the symlinks listed are unlikely to cause issues, such as `/usr/lib/x86_64-linux-gnu/libc.so.6`.
