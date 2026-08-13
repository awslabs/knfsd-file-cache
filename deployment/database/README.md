# KNFSD FSID Database

This module deploys an Amazon DynamoDB table for use with the [external fsidd service](../docs/fsids.md) and [auto re-export](../docs/auto-re-export.md).

> NOTE: This module is deployed automatically by `terraform-module-knfsd` when `FSID_MODE="external"` (unless you disable `FSID_DATABASE_DEPLOY`).

## Table Design

The table is created with on-demand capacity (`PAY_PER_REQUEST`), a single string partition key `id`, server-side encryption with the AWS managed key (`aws/dynamodb`), point-in-time recovery enabled, and deletion protection controlled by `DELETION_PROTECTION`.

This schema is the canonical documentation of the data layout used by the [`knfsd-fsidd`](../../image/resources/knfsd-fsidd/) daemon. There are three item types, all sharing the same partition key attribute `id`:

| `id` (partition key)  | Attributes             | Purpose                                         |
| --------------------- | ---------------------- | ----------------------------------------------- |
| `PATH#<export-path>`  | `fsid` (N), `path` (S) | Forward lookup: export path to FSID number.     |
| `FSID#<n>`            | `fsid` (N), `path` (S) | Reverse lookup: FSID number to export path.     |
| `COUNTER`             | `next_fsid` (N)        | Allocation sequence: the next FSID to hand out. |

The reverse lookup is stored as a base-table item (not a Global Secondary Index) so that both directions can be read with `ConsistentRead = true`, removing any eventual-consistency window.

### FSID allocation

`AllocateFSID` uses a conditional-write claim pattern inside a single `TransactWriteItems` call so that when multiple KNFSD instances race to allocate an FSID for the same path, exactly one writer wins:

1. Read `COUNTER` (`ConsistentRead`) to learn the next FSID `n` (the counter is seeded so the first FSID is `1`, preserving the `fsid > 0` invariant).
2. In one atomic transaction:
   * Update `COUNTER` to `n + 1`, conditional on it still holding `n` (or still not existing when allocating the first FSID).
   * Put `PATH#<path>`, conditional on the item not existing.
   * Put `FSID#<n>`, conditional on the item not existing.
3. If the counter condition fails (another instance advanced the counter first), re-read the counter and retry.
4. If the `PATH#` condition fails (another instance claimed the same path first), the daemon re-reads the winning mapping and returns it.

Either everything commits, or nothing does: FSIDs are gap-free sequential integers and the `PATH#`/`FSID#` items can never diverge.

### Reuse across deployments

The table name flows through the module outputs into `FSID_DATABASE_CONFIG`, so a single table can be shared by multiple KNFSD proxy clusters (see [Fanout](../docs/fanout.md)). The daemon addresses the table by `(region, table name)` over the regional DynamoDB HTTPS API, so reuse works across VPCs with zero networking setup. Cross-account reuse is not supported (the `FSID_DATABASE_IAM_POLICY` policy ARN can only be attached within the same account).

## Inputs

| Variable                   | Description                                                                                                                                                                                                 | Required | Default       |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|---------------|
| `NAME`                     | The base name of the DynamoDB table. When set, the table will be named `<NAME>-fsids` (e.g. `mycluster-fsids`). If the name is left blank a random table name will be generated based on `NAME_PREFIX`. \*  | False    | `""`          |
| `NAME_PREFIX`              | Prefix to use when generating a random DynamoDB table name (used when `NAME` is left blank). The prefix will be suffixed with a hyphen and 8 random letters/digits (e.g. `knfsd-fsids-a1b2c3d4`).           | False    | `knfsd-fsids` |
| `DELETION_PROTECTION`      | Whether or not to allow Terraform to destroy the DynamoDB table. Unless this field is set to false in Terraform state, a `terraform destroy` or `terraform apply` command that deletes the table will fail. | False    | `true`        |
| `FSID_DATABASE_IAM_POLICY` | ARN of a custom IAM policy granting DynamoDB item-level access to the FSID table. \**                                                                                                                       | False    | `""`          |

\* The table name must be unique within your AWS account in the current AWS Region.

\*\* When set, the module still deploys the DynamoDB table but skips creating the `aws_iam_policy`, using the provided policy ARN instead (required when the deploying role lacks `iam:CreatePolicy`).

## Outputs

| Output          | Description                                                                                                                                                                                               |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `db_iam_policy` | The ARN of the IAM policy granting the DynamoDB item-level actions used by `knfsd-fsidd` (`dynamodb:ConditionCheckItem`, `DescribeTable`, `GetItem`, `PutItem`, `UpdateItem`), scoped to this table only. |
| `region`        | The AWS region hosting the DynamoDB table.                                                                                                                                                                |
| `table_name`    | The name of the DynamoDB table.                                                                                                                                                                           |
