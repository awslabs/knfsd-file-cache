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

The main difference between the standard NFS `fsidd` service and the `knfsd-fsidd` service is that the standard `fsidd` service uses a local sqlite database, while the `knfsd-fsidd` service uses an Amazon RDS PostgreSQL instance.

### Static

FSID numbers are explicitly allocated to exports on start-up by the `proxy-startup.sh` script.

This mode is only recommended when using `EXPORT_MAP` to explicitly define which exports are re-exported (and in which order) to ensure all the knfsd proxies in the cluster assign the same FSID number to each export.

If using auto-discovery there is a risk that if a proxy instance is rebooted or replaced the exports might have changed (new exports added or exports removed). If this happens the same export will have different FSID numbers on different proxy instances.

### Local

Each export is automatically allocated an FSID number by the `mountd` service using the standard NFS `fsidd` service. The mappings between FSID and export path are stored in a local SQLite database.

Local is not recommended for production and is only intended for testing with single instance proxy clusters. Because the SQLite database is stored locally on the knfsd proxy instance, if you're using multiple proxy instances each instance could allocate a different FSID to the same export (or the same FSID to different exports).

Even with a single instance, there's still a risk if the instance is replaced due to a failing health check. When the instance is replaced the new instance will start with an empty SQLite database. When existing clients re-connect, they could see inconsistent FSIDs.

### External

Each export is automatically allocated an FSID number by the `mountd` service using the `knfsd-fsidd` service. This uses an Amazon RDS PostgreSQL instance to store the mappings between FSID and export path. This ensures that all the instances in cluster use the same FSID for each export path.

This is the recommended and default deployment option for all knfsd proxy configurations as its the easiest to configure and ensures the consistency of FSIDs across the cluster.

> NOTE: The knfsd proxy instance(s) will need to be able to access the Amazon RDS PostgreSQL instance.

### Using the Database Terraform module

The Database Terraform module in [deployment/database](../database/README.md) can be used to create an Amazon RDS PostgreSQL instance suitable for use by a knfsd proxy cluster. This is the same module that the KNFSD Terraform module uses internally.

```terraform
# Create a RDS PostgreSQL database instance for use by KNFSD proxy cluster(s)

module "fsid_database" {
  source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.26"
  SUBNET = "subnet-038e337f0ff4cd53f"
}

output "db_address" {
  value = module.fsid_database.address
}

output "db_port" {
  value = module.fsid_database.port
}

output "db_user" {
  value = module.fsid_database.db_user
}

output "db_name" {
  value = module.fsid_database.db_name
}

output "db_iam_policy" {
  value = module.fsid_database.db_iam_policy
}

output "master_username" {
  value = module.fsid_database.username
}
```

### Amazon RDS PostgreSQL configuration

The FSID service is not resource intensive, and does not require much storage. As such the minimum database instance type of `db.t4g.micro` should be sufficient for most configurations.

By default, the RDS database is deployed with IAM authentication enabled and deletion protection disabled.

### IAM roles

The standard FSID configuration uses the IAM instance profile (e.g. `knfsd-instance-role`) assigned to the knfsd proxy instance to authenticate the PostgreSQL database user (e.g. `fsidd`) with the RDS database using IAM.

The IAM instance role is automatically created by the `terraform-module-knfsd` module in `iam.tf`.

### FSID Database Configuration

When using `FSID_MODE="external"` the `knfsd-fsidd` service can be configured by setting `FSID_DATABASE_CONFIG`.

> NOTE: When `FSID_DATABASE_DEPLOY = true` the configuration will be generated for you. However, if you set `FSID_DATABASE_DEPLOY = false` you will need to provide the database configuration.

The configuration supports the following options:

* `socket` (Optional) - The unix socket to listen on for incoming FSID requests from `mountd`. This *must* match the value configured in `/etc/nfs.conf`. Default `/run/knfsd-fsidd.sock`.

* `debug` (Optional) - Enabled writing verbose debug output to `stderr`. Default `false`.

* `cache` (Optional) - Enables caching FSID mappings to avoid querying FSID database. Setting this to false can result in excessive SQL queries and slow performance and is only intended for debugging. Default `true`.

---

The `[database]` section supports:

* `url` (Required) - A [`pgxpool` URL](https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool#ParseConfig). The `host`, `port`, `user`, and `dbname` options must be set. Authentication will be handled by the AWS GO v2 SDK.

* `iam-auth` (Optional) - Set to `true` to enable automatic IAM authentication. Using automatic IAM authentication is recommended. The knfsd proxy instance will use the IAM instance profile to authenticate with RDS PostgreSQL database. If set to `false` the database user will need to authenticate with the database using the additional `password=` parameter in the `url=` option. Default `true`.

* `table-name` (Required) - The name of table to store the FSID mappings for the proxy cluster. It is recommended that each proxy cluster has its own unique table name. Default `fsids`.

* `create-table` (Optional) - When `true` the `knfsd-fsidd` service will try to create its own table on start up. If set to `false` the table must already exist. See [knfsd-fsidd/schema.sql](../../image/resources/knfsd-fsidd/schema.sql). Default `true`.

---

The `[metrics]` section supports:

* `enabled` (Optional) - Set to `true` to report metrics such as the number of requests, SQL operations, etc. Default `true`.

* `endpoint` (Optional) - The endpoint to report metrics using the OTLP format. The endpoint must support GRPC. Default `unix:///run/knfsd-metrics.sock`.

* `insecure` (Optional) - Set to `true` to allow sending metrics via GRPC without any encryption or endpoint verification. Default `true`.

* `interval` (Optional) - How frequently to send metrics. Default `1m`.

### Example FSID database configuration

```ini
socket=/run/knfsd-fsidd.sock

[database]
url=host=fsids.jazg4zscprls.eu-west-2.rds.amazonaws.com port=5432 user=fsidd dbname=fsids
iam-auth=true
table-name=fsids
create-table=true

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

By default, when `FSID_MODE="external"` the deployment Terraform configuration will create an Amazon RDS PostgreSQL instance for the proxy cluster. This is the simplest, and recommended option. `FSID_DATABASE_CONFIG` and `FSID_DATABASE_IAM_POLICY` are automatically generated for you.

However, if you want to create your own database, such as to use a single Amazon RDS PostgreSQL database for multiple knfsd proxy clusters you can set `FSID_DATABASE_DEPLOY=false`. You will need to provide the database configuration and IAM policy via setting the `FSID_DATABASE_CONFIG` (JSON object) and `FSID_DATABASE_IAM_POLICY` (ARN) variables for each additional knfsd proxy cluster deployed. See the [Fanout](fanout.md) example for more details.

The `FSID_DATABASE_CONFIG` JSON object supports the following custom options:

* `db_address` (Required) - The address of the PostgreSQL instance.
* `db_port` (Required) - The port of the PostgreSQL instance.
* `db_user` (Required) - The user to authenticate with the PostgreSQL instance.
* `db_name` (Required) - The name of the database to use for the FSID mappings.
* `enable_metrics` (Required) - Whether to enable metrics for the FSID database.

```json
FSID_DATABASE_CONFIG = {
  db_address     = "fsids.jazg4zscprls.eu-west-2.rds.amazonaws.com"
  db_port        = 5432
  db_user        = "fsidd"
  db_name        = "fsids"
  enable_metrics = true
}
// replace ${} variables with the appropriate values
FSID_DATABASE_IAM_POLICY = "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${aws_db_instance.fsids.id}/${local.db_user}"
```

Before deploying the knfsd proxy cluster, create a suitable Amazon RDS PostgreSQL database (the `knfsd-fsidd` service only supports PostgreSQL).

### Database Security

SSL/TLS v1.3 is enabled and enforced by default on all connections to the FSIDS PostgreSQL database. Optionally, you can enforce [verification](https://www.postgresql.org/docs/current/libpq-ssl.html) of the server certificate is issued by a trusted CA and that the requested server hostname matches that in the certificate, by setting the additional `sslmode` and `sslrootcert` parameters in the DSN connection string `url=` in the `[database]` section of the [knfsd-fsidd.conf.tftpl](../terraform-module-knfsd/resources/knfsd-fsidd.conf.tftpl) file. PostgreSQL also supports other [parameter key words](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-PARAMKEYWORDS) that can be configured.

AWS provides a certificate bundle for each region that can be used to verify the server certificate. The following commands download the root certificate CA bundle for ALL regions within a certain AWS partition ([Commercial, GovCloud](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html#UsingWithRDS.SSL.CertificatesDownload), or [China](https://docs.amazonaws.cn/en_us/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html#UsingWithRDS.SSL.CertificatesDownload)) and save it as `aws-rds-<partition>.pem`. Alternatively, you can download the certificate bundle for a specific region.

```bash
# Use the appropriate curl command for the required AWS partition
curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o aws-rds-commercial.pem
curl -fsSL https://truststore.pki.us-gov-west-1.rds.amazonaws.com/global/global-bundle.pem -o aws-rds-govcloud.pem
curl -fsSL https://rds-truststore.s3.cn-north-1.amazonaws.com.cn/global/global-bundle.pem -o aws-rds-china.pem
```

The following example configuration uses the `aws-rds-commercial.pem` certificate bundle for the `eu-west-2` region. Ensure you provide a valid file path to the certificate bundle in the `sslrootcert` parameter.

```ini
[database]
url=host=fsids.jazg4zscprls.eu-west-2.rds.amazonaws.com port=5432 user=fsidd dbname=fsids sslmode=verify-full sslrootcert=/path/to/aws-rds-commercial.pem
```
