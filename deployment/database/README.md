# KNFSD FSID Database

This module deploys an Amazon RDS PostgreSQL database for use with the [external fsidd service](../docs/fsids.md) and [auto re-export](../docs/auto-re-export.md).

> NOTE: This module is deployed automatically by `terraform-module-knfsd` when `FSID_MODE="external"` (unless you disable `FSID_DATABASE_DEPLOY`).

## Inputs

* `SUBNET` - (Required) The subnet ID to use for deployment of the Amazon RDS DB instance. Example: `subnet-038e337f0ff4cd53f`.

* `FSID_DB_SUBNET_GROUP_NAME` - (Optional) The name of the Amazon RDS DB subnet group to use for the FSID database. Required when using a non-default VPC. Defaults to `null`.

    **NOTE:** When deploying a database; a default VPC will cause Terraform to automatically generate a `default` DB subnet group, containing at least 2 subnets, each in a different availability zone. If you are using a non-default VPC for the database, you should create a DB subnet group in RDS, containing at least 2 subnets, each in a different availability zone, and then specify `FSID_DB_SUBNET_GROUP_NAME`. The single AZ deployment of the database will still target the availability zone of the provided subnet via `var.SUBNET`. The RDS DB subnet group must contain the subnet defined in `var.SUBNET`.

    **INFO:** AWS mandates that the DB subnet group must contain at least 2 subnets, each in a different availability zone, just in case you want to convert the database to a multi-AZ deployment in the future or in the case of AZ failure, you will have the ability to failover manually to another AZ.

* `VPC_CIDR` - (Optional) List of CIDR blocks to allow in security group rules. If empty, the primary VPC CIDR block is used. For secondary VPC CIDRs or cross-VPC access with VPC peering, you must explicitly provide the full list. Defaults to `[]`.

* `NAME_PREFIX` - (Optional) Prefix to use when generating a RDS DB instance name. The name will be suffixed with a hyphen and 8 random letters/digits. Defaults to `fsids`.

* `NAME` - (Optional) The name of the RDS DB instance. If the name is left blank a random name will be generated based on `NAME_PREFIX`.

* `INSTANCE_CLASS` - (Optional) The EC2 instance type to use. Must be a supported RDS PostgreSQL instance class. Defaults to `db.t4g.micro`.

* `DELETION_PROTECTION` - (Optional) Whether or not to allow Terraform to destroy the instance. Unless this field is set to false in Terraform state, a `terraform destroy` or `terraform apply` command that deletes the instance will fail. Defaults to `true`.

* `ENABLE_PUBLIC_IP` - (Optional) Whether to deploy the database with a public IP address. When the DB instance is publicly accessible and you connect from outside of the DB instance's Virtual Private Cloud (VPC), its Domain Name System (DNS) endpoint resolves to the public IP address. When you connect from within the same VPC as the DB instance, the endpoint resolves to the private IP address. Access to the DB instance is ultimately controlled by the EC2 security group it uses. Public access isn't permitted if the security group assigned to the DB instance doesn't permit it. When the DB instance isn't publicly accessible, it is an internal DB instance with a DNS name that resolves to a private IP address. Defaults to `false`.

* `MASTER_USERNAME` - (Optional) The master username for the database. Password is stored in AWS Secrets Manager. Defaults to `postgres`.

* `ASSUME_ROLE_ARN` - (Optional) The ARN of the IAM role to assume for AWS CLI commands in local-exec provisioners for CI/CD pipelines. If not provided, no role assumption will be performed and the local-exec provisioner will use the existing AWS credentials from the environment. Example: `arn:aws:iam::123456789012:role/DeploymentRole`. Defaults to `null`.

## Outputs

* `db_address` - The hostname of the RDS DB instance.

* `db_iam_policy` - The ARN of the IAM policy for `rds-db:connect` database access.

* `db_name` - The name of the PostgreSQL database.

* `db_port` - The port of the RDS DB instance.

* `db_user` - The DB username to access the PostgreSQL database.

* `master_username` - The master username for the PostgreSQL database. Password is stored in AWS Secrets Manager.
