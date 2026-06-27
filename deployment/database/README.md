# KNFSD FSID Database

This module deploys an Amazon RDS PostgreSQL database for use with the [external fsidd service](../docs/fsids.md) and [auto re-export](../docs/auto-re-export.md).

> NOTE: This module is deployed automatically by `terraform-module-knfsd` when `FSID_MODE="external"` (unless you disable `FSID_DATABASE_DEPLOY`).

## Inputs

* `SUBNET` - (Required) The subnet ID to use for deployment of the Amazon RDS DB instance. Example: `subnet-038e337f0ff4cd53f`.

* `FSID_DB_SUBNET_GROUP_NAME` - (Optional) The name of an existing Amazon RDS DB subnet group to use for the FSID database. Required when using a non-default VPC, unless `FSID_DB_SUBNET_IDS` is used instead. Defaults to `null`.

* `FSID_DB_SUBNET_IDS` - (Optional) List of 2+ subnet IDs in different availability zones; the module will automatically create an `aws_db_subnet_group` from the supplied subnets. Must include the subnet in `var.SUBNET`, all subnets must belong to the same VPC as `var.SUBNET`, and the subnets must span at least 2 availability zones (all enforced at `terraform plan` time). Mutually exclusive with `FSID_DB_SUBNET_GROUP_NAME`. Defaults to `null`.

    **NOTE:** The `database` module supports three ways to choose where the RDS DB instance is placed:

    | Scenario                                                   | `FSID_DB_SUBNET_GROUP_NAME` | `FSID_DB_SUBNET_IDS`                 | Result                                                             |
    | ---------------------------------------------------------- | --------------------------- | ------------------------------------ | ------------------------------------------------------------------ |
    | Default VPC (default)                                      | `null`                      | `null`                               | AWS's regional `default` DB subnet group is used automatically.    |
    | Non-default VPC, pre-existing DB subnet group              | `"my-group"`                | `null`                               | Module uses the DB subnet group you already created.               |
    | Non-default VPC, let the module create the DB subnet group | `null`                      | `["subnet-aaa...", "subnet-bbb..."]` | Module creates `aws_db_subnet_group` from the supplied subnet IDs. |

    Setting both variables at the same time is an error. The single-AZ deployment of the DB instance still targets the availability zone of `var.SUBNET`.

    **INFO:** AWS mandates that the DB subnet group must contain at least 2 subnets, each in a different availability zone, just in case you want to convert the database to a multi-AZ deployment in the future or in the case of AZ failure, you will have the ability to failover manually to another AZ.

* `VPC_CIDR` - (Optional) List of CIDR blocks to allow in security group rules. If empty, the primary VPC CIDR block is used. For secondary VPC CIDRs or cross-VPC access with VPC peering, you must explicitly provide the full list. Defaults to `[]`.

* `NAME_PREFIX` - (Optional) Prefix to use when generating a RDS DB instance name. The name will be suffixed with a hyphen and 8 random letters/digits. Defaults to `fsids`.

* `NAME` - (Optional) The name of the RDS DB instance. If the name is left blank a random name will be generated based on `NAME_PREFIX`.

* `INSTANCE_CLASS` - (Optional) The EC2 instance type to use. Must be a supported RDS PostgreSQL instance class. Defaults to `db.t4g.micro`.

* `DELETION_PROTECTION` - (Optional) Whether or not to allow Terraform to destroy the instance. Unless this field is set to false in Terraform state, a `terraform destroy` or `terraform apply` command that deletes the instance will fail. Defaults to `true`.

* `ENABLE_PUBLIC_IP` - (Optional) Whether to deploy the database with a public IP address. When the DB instance is publicly accessible and you connect from outside of the DB instance's Virtual Private Cloud (VPC), its Domain Name System (DNS) endpoint resolves to the public IP address. When you connect from within the same VPC as the DB instance, the endpoint resolves to the private IP address. Access to the DB instance is ultimately controlled by the EC2 security group it uses. Public access isn't permitted if the security group assigned to the DB instance doesn't permit it. When the DB instance isn't publicly accessible, it is an internal DB instance with a DNS name that resolves to a private IP address. Defaults to `false`.

* `MASTER_USERNAME` - (Optional) The master username for the database. Password is stored in AWS Secrets Manager. Defaults to `postgres`.

* `ASSUME_ROLE_ARN` - (Optional) The ARN of the IAM role to assume for AWS CLI commands in local-exec provisioners for CI/CD pipelines. If not provided, no role assumption will be performed and the local-exec provisioner will use the existing AWS credentials from the environment. Example: `arn:*:iam::123456789012:role/DeploymentRole`. Defaults to `null`.

## Outputs

* `db_address` - The hostname of the RDS DB instance.

* `db_iam_policy` - The ARN of the IAM policy for `rds-db:connect` database access.

* `db_name` - The name of the PostgreSQL database.

* `db_port` - The port of the RDS DB instance.

* `db_user` - The DB username to access the PostgreSQL database.

* `master_username` - The master username for the PostgreSQL database. Password is stored in AWS Secrets Manager.
