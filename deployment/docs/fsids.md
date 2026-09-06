# Filesystem Identifiers (FSIDs)

Almost all NFS operations use an opaque file handle to identify the file or directory that is the target of the operations (such as for reads and writes). The exact format depends upon the NFS server, for Linux's kernel NFS server (knfsd) the handle consists of two main parts, a filesystem identifier (FSID) and an inode number.

Every exported filesystem requires a unique filesystem identifier (FSID). In a standard NFS server the NFS service can automatically derive the FSID number for an export from the underlying filesystem's UUID or the hardware's device ID.

This option is not available for a knfsd proxy when re-exporting. The knfsd proxy cannot reuse the source server's FSID value as this could conflict with local filesystems on the proxy (or other source services if the proxy has multiple sources).

As such each export on the proxy has to be explicitly allocated a unique FSID number. This number should ideally be the same for all proxy instances in the cluster to avoid I/O errors or data corruption if a client switches proxy instance (e.g. when using the load balancer).

## Importance of unique FSID numbers

When a client needs to access a file or directory the client uses the LOOKUP operation to convert a file's name to a file handle. After that the client will continue to use the file handle it received for any READ or WRITE operations until the client closes the file.

The NFS protocol (and NFS client) assumes that this handle will remain stable in the face of communication issues. If TCP connection is interrupted, the client will reconnect and carry on using the same file handle.

This can lead to two possible issues if we are not careful:

1. The FSID and inode is valid, but maps to the wrong file resulting in data corruption.
2. The FSID or inode becomes invalid resulting in an I/O error.

As an example of how this can occur, assume we have two filesystems on a proxy:

* `/files` with FSID 1
* `/archive` with FSID 2

The client has connected and is reading data on `/files/`. The NFS server crashes and reboots, but on start-up allocates different FSIDs to the exports.

* `/files` with FSID 2
* `/archive` with FSID 1

The client retries the TCP connection until the NFS server is available, then carries on its previous READ operation. However, the file handle for the READ operation has FSID 1, which was previously `/files` but is now `/archive`.

The NFS server will look for a file on `/archive` with the inode from the file handle. At this point one of two things may happen:

1. `/archive` contains a file with the inode number. The NFS server replies with data from the wrong file in the middle of the data that was previously read.

2. `/archive` does not contain that inode number resulting in an I/O error.

With a knfsd proxy cluster there are two main ways this issue with FSIDs can occur:

1. When a knfsd proxy instance is replaced (e.g. due to a failed health check) the new instance does not assign the same FSIDs to each export. This can be due to:

   * The Auto-Scaling Group (ASG) was updated with a change to the exports in `EXPORT_MAP`.

   * Using auto-discovery, and the source server's exports have changed (e.g. due to volumes being added or removed).

   * Using auto re-export, as FSIDs are assigned based on the order clients access the nested volumes.

2. A client re-connects to a different knfsd proxy instance (e.g. due to load balancing) and the knfsd proxy cluster has inconsistent FSIDs.

These issues can be avoided by storing the mappings between FSID and export path in an external database by using `FSID_MODE="external"`.

## FSID Mode

The `FSID_MODE` variable controls how FSID numbers are allocated to exports. There are two main options; `static` or using an FSID service. For the FSID service there are two options available. The standard NFS `fsidd` service, or the `knfsd-fsidd` service.

* `static` - FSID numbers are explicitly allocated to exports on start-up.
* `local` - FSID numbers are automatically allocated to exports by the standard NFS `fsidd` service.
* `external` - FSID numbers are automatically allocated to exports by the `knfsd-fsidd` service.

The main difference between the standard NFS `fsidd` service and the `knfsd-fsidd` service is that the standard `fsidd` service uses a local sqlite database, while the `knfsd-fsidd` service uses an Amazon DynamoDB table.

### Static

FSID numbers are explicitly allocated to exports on start-up by the `proxy-startup.sh` script.

This mode is only recommended when using `EXPORT_MAP` to explicitly define which exports are re-exported (and in which order) to ensure all the knfsd proxies in the cluster assign the same FSID number to each export.

If using auto-discovery there is a risk that if a proxy instance is rebooted or replaced the exports might have changed (new exports added or exports removed). If this happens the same export will have different FSID numbers on different proxy instances.

### Local

Each export is automatically allocated an FSID number by the `mountd` service using the standard NFS `fsidd` service. The mappings between FSID and export path are stored in a local SQLite database.

Local is not recommended for production and is only intended for testing with single instance proxy clusters. Because the SQLite database is stored locally on the knfsd proxy instance, if you're using multiple proxy instances each instance could allocate a different FSID to the same export (or the same FSID to different exports).

Even with a single instance, there's still a risk if the instance is replaced due to a failing health check. When the instance is replaced the new instance will start with an empty SQLite database. When existing clients re-connect, they could see inconsistent FSIDs.

### External

Each export is automatically allocated an FSID number by the `mountd` service using the `knfsd-fsidd` service. This uses an Amazon DynamoDB table to store the mappings between FSID and export path. This ensures that all the instances in a cluster use the same FSID for each export path.

This is the recommended and default deployment option for all knfsd proxy configurations as its the easiest to configure and ensures the consistency of FSIDs across the cluster.

> NOTE: The knfsd proxy instance(s) accesses the DynamoDB table using the regional DynamoDB HTTPS API using the IAM instance profile for authentication. No VPC or subnet connectivity to a database host is required. However, if the proxy subnets have no internet access, add a (free) DynamoDB Gateway VPC endpoint; see [VPC Endpoints](vpc-endpoints.md).

### Using the Database Terraform module

The Database Terraform module in [deployment/database](../database/README.md) can be used to create an Amazon DynamoDB table suitable for use by a knfsd proxy cluster. This is the same module that the KNFSD Terraform module uses internally. The table schema and FSID allocation logic are documented in the [database module README](../database/README.md).

```terraform
# Create a DynamoDB FSID table for use by KNFSD proxy cluster(s)

module "fsid_database" {
  source = "github.com/awslabs/knfsd-file-cache//deployment/database?ref=v1.1.0-beta.3"
}

output "table_name" {
  value = module.fsid_database.table_name
}

output "region" {
  value = module.fsid_database.region
}

output "db_iam_policy" {
  value = module.fsid_database.db_iam_policy
}
```

### Amazon DynamoDB configuration

The FSID service is not resource intensive, and does not require much storage. The DynamoDB table is created with on-demand capacity (`PAY_PER_REQUEST`), so there is no instance to size and you only pay per request; for this workload the cost is negligible.

By default, the table is deployed with server-side encryption (AWS managed key), point-in-time recovery, and deletion protection enabled.

### IAM roles

The standard FSID configuration uses the IAM instance profile (e.g. `knfsd-instance-role`) assigned to the knfsd proxy instance to authenticate with DynamoDB. The `database` module creates a least-privilege IAM policy granting only the item-level actions the daemon uses (`dynamodb:ConditionCheckItem`, `DescribeTable`, `GetItem`, `PutItem`, `UpdateItem`) scoped to the FSID table only, and the `terraform-module-knfsd` module attaches it to the instance role.

The IAM instance role is automatically created by the `terraform-module-knfsd` module in `iam.tf`.

### FSID Database Configuration

When using `FSID_MODE="external"` the `knfsd-fsidd` service can be configured by setting `FSID_DATABASE_CONFIG`.

> NOTE: When `FSID_DATABASE_DEPLOY = true` the configuration will be generated for you. However, if you set `FSID_DATABASE_DEPLOY = false` you will need to provide the database configuration.

The configuration supports the following options:

* `socket` (Optional) - The unix socket to listen on for incoming FSID requests from `mountd`. This *must* match the value configured in `/etc/nfs.conf`. Default `/run/knfsd-fsidd.sock`.

* `debug` (Optional) - Enabled writing verbose debug output to `stderr`. Default `false`.

* `cache` (Optional) - Enables caching FSID mappings to avoid querying FSID database. Setting this to false can result in excessive database queries and slow performance and is only intended for debugging. Default `true`.

---

The `[database]` section supports:

* `table-name` (Required) - The name of the DynamoDB table storing the FSID mappings for the proxy cluster. Table names only need to be unique per AWS account and region; the Terraform `database` module generates a unique name automatically.

* `region` (Optional) - The AWS region hosting the DynamoDB table. Because DynamoDB is a regional HTTPS API, `(region, table-name)` fully identifies the table. If absent, the daemon falls back to the instance's own region (via IMDSv2). The Terraform-rendered configuration always sets it explicitly.

* `endpoint` (Optional) - Override the DynamoDB endpoint URL. Only intended for testing against `DynamoDB Local` container. Default empty (use the standard regional endpoint).

---

The `[metrics]` section supports:

* `enabled` (Optional) - Set to `true` to report metrics such as the number of requests, database operations, etc. Default `true`.

* `endpoint` (Optional) - The endpoint to report metrics using the OTLP format. The endpoint must support GRPC. Default `unix:///run/knfsd-metrics.sock`.

* `insecure` (Optional) - Set to `true` to allow sending metrics via GRPC without any encryption or endpoint verification. Default `true`.

* `interval` (Optional) - How frequently to send metrics. Default `1m`.

### Example FSID database configuration

```ini
socket=/run/knfsd-fsidd.sock

[database]
table-name=knfsd-fsids-a1b2c3d4
region=eu-west-2

[metrics]
enabled=true
# The custom knfsd-metrics-agent has been configured to listen on this socket
# and forward metrics to Amazon CloudWatch.
endpoint=unix:///run/knfsd-metrics.sock
# TLS security is not required as unix domain sockets can only be accessed on
# the local machine. This socket will be protected by standard unix permissions.
insecure=true
interval=1m
```

### Custom Database Configuration

By default, when `FSID_MODE="external"` the deployment Terraform configuration will create an Amazon DynamoDB table for the proxy cluster. This is the simplest, and recommended option. `FSID_DATABASE_CONFIG` and `FSID_DATABASE_IAM_POLICY` are automatically generated for you.

However, if you want to create your own table, such as to use a single Amazon DynamoDB table for multiple knfsd proxy clusters, you can set `FSID_DATABASE_DEPLOY=false`. You will need to provide the database configuration and IAM policy via setting the `FSID_DATABASE_CONFIG` (object) and `FSID_DATABASE_IAM_POLICY` (ARN) variables for each additional knfsd proxy cluster deployed. See the [Fanout](fanout.md) example for more details.

`FSID_DATABASE_IAM_POLICY` can also be set while leaving `FSID_DATABASE_DEPLOY=true`. In that case the DynamoDB table is still deployed, but the deployment skips creating the DynamoDB access IAM policy and attaches the policy you provide instead. This is intended for deployment roles that are denied `iam:CreatePolicy`. See [IAM Permissions](../../docs/iam.md) for details.

The `FSID_DATABASE_CONFIG` object supports the following custom options:

* `table_name` (Required) - The name of the DynamoDB table storing the FSID mappings.
* `region` (Required) - The AWS region hosting the DynamoDB table.
* `enable_metrics` (Required) - Whether to enable metrics for the FSID database.

```json
// replace values with the outputs of your own database deployment
FSID_DATABASE_CONFIG = {
  table_name     = "knfsd-fsids-a1b2c3d4"
  region         = "eu-west-2"
  enable_metrics = true
}
FSID_DATABASE_IAM_POLICY = "arn:aws:iam::123456789012:policy/knfsd-fsids-a1b2c3d4-dynamodb-auth-policy"
```

Before deploying the knfsd proxy cluster, create a suitable Amazon DynamoDB table (single string partition key `id`; see the [database module README](../database/README.md) for the full schema) and an IAM policy granting the item-level actions listed under [IAM roles](#iam-roles) on that table.

#### Reuse boundaries

* **Same account, any VPC**: supported. DynamoDB is a regional HTTPS API; `(region, table-name)` plus SigV4 credentials from the instance role fully identify the table, no network routing to a database host is needed.
* **Cross-account**: not supported. `FSID_DATABASE_IAM_POLICY` is an IAM policy ARN which can only be attached to instance roles within the same account.

### Database Security

All connections to DynamoDB use HTTPS (TLS) with SigV4 request signing via the AWS SDK; there are no database passwords or connection strings to manage. Data at rest is encrypted with the AWS managed key (`aws/dynamodb`). Access is controlled entirely through IAM: only principals with the item-level actions on the table ARN (such as the knfsd instance role via `FSID_DATABASE_IAM_POLICY`) can read or write the FSID mappings.
