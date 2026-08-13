# Smoke Tests

The smoke tests provision an end-to-end KNFSD environment in AWS and verify the basic correctness of a freshly-built KNFSD proxy AMI. They run locally (or from the dev container) against an existing VPC subnet, driven entirely by the `Makefile` in this directory.

For every run, the harness performs the following steps:

1. Deploys (via [`modules/source-nfs`](modules/source-nfs)) an EC2 instance with local NVMe + XFS that exports `/files` over NFS to the VPC CIDR.
2. Deploys a KNFSD proxy through the [`deployment/terraform-module-knfsd`](../../deployment/terraform-module-knfsd) module using the AMI under test.
3. Deploys a single Ubuntu test client EC2 instance (via [`modules/nfs-client`](modules/nfs-client), with IMDSv2 enforced) that is tagged with `knfsd-file-cache:source-host` and `knfsd-file-cache:proxy-host`.
4. Copies the compiled `remote.test` binary onto the client over `scp` and executes it via `sudo` over `ssh`, both tunnelled over SSM (see [SSH connectivity](#ssh-connectivity)).
5. Tears every AWS resource down.

The Golang compiled `remote.test` binary reads `source_host` / `proxy_host` from EC2 instance tags via IMDSv2 and exercises mounts through the proxy. The `remote.test` binary is compiled using the `build-remote` target via the `Makefile`. Because the binary runs on the remote NFS client (not the machine driving the tests), `build-remote` cross-compiles it for `GOOS=linux GOARCH=$(TARGET_ARCH)`. `TARGET_ARCH` defaults to `amd64` to match the Terraform `ARCH` default and is independent of the dev-container host architecture; override it (e.g. `make test TARGET_ARCH=arm64`) to match a non-default client `ARCH`.

The smoke-test Terraform in [`terraform/`](terraform/) wires three modules — [`modules/source-nfs`](modules/source-nfs), [`deployment/terraform-module-knfsd`](../../deployment/terraform-module-knfsd), and [`modules/nfs-client`](modules/nfs-client) — plus the self-created security groups in [`terraform/network.tf`](terraform/network.tf).

## Prerequisites

The smoke-test Terraform creates only the per-run resources (source NFS server, KNFSD proxy ASG, NFS client) inside an **existing** VPC. It needs a `SUBNET` with outbound internet and a `PROXY_AMI`; the source-NFS and NFS-client security groups are **self-created from the subnet's VPC CIDR**, so the harness runs standalone against an existing or default VPC with no pre-wired security groups.

Before a run you need:

1. A subnet whose route table reaches the internet (NAT, or public subnet + IGW with a public IP) so the instances' SSM agents reach the SSM endpoints and `apt`/`snap` installs succeed. A default-VPC public subnet works.
2. A KNFSD proxy AMI ID to test, supplied directly via `PROXY_AMI`.

The smoke-test Terraform consumes the following inputs (defined in [`terraform/variables.tf`](terraform/variables.tf)):

| Variable                      | Type   | Source                                                                                                                                                | Required | Default       |
|-------------------------------|--------|-------------------------------------------------------------------------------------------------------------------------------------------------------|----------|---------------|
| `REGION`                      | string | The AWS region in which the VPC/subnet live.                                                                                                          | True     |               |
| `SUBNET`                      | string | A subnet ID with outbound internet (NAT or public + IGW) so the SSM agent and `apt` work.                                                             | True     |               |
| `PROXY_AMI`                   | string | KNFSD proxy AMI ID under test, supplied directly.                                                                                                     | True     |               |
| `ASSOCIATE_PUBLIC_IP_ADDRESS` | bool   | Force a public IP on all instances (`null` = inherit subnet). Set `true` for a public-subnet run with no NAT; SGs still block all ingress.            | False    | `null`        |
| `ARCH`                        | string | Selects the Ubuntu 26.04 client AMI resolved from Canonical's SSM parameter. Must be: `amd64` or `arm64`.                                             | False    | `amd64`       |
| `INSTANCE_TYPE`               | string | EC2 instance type for the test client; defaults to `m6i.2xlarge`. Must match `ARCH` (e.g. `m7g.2xlarge` for `arm64`).                                 | False    | `m6i.2xlarge` |
| `FSID_MODE`                   | string | `FSID_MODE` passed to the KNFSD module. `external` deploys the DynamoDB FSID table and enables the FSID table checks; `static` and `local` skip them. | False    | `external`    |

The Terraform self-creates VPC-CIDR-scoped source-NFS and client security groups (see [`terraform/network.tf`](terraform/network.tf)) opening only the required NFS ports between the instances and the proxy.

## Required AWS permissions

The driver and the underlying Terraform need the canonical IAM policies documented in [`docs/iam`](../../docs/iam):

* [`docs/iam/packer.json`](../../docs/iam/packer.json)
* [`docs/iam/tf-required.json`](../../docs/iam/tf-required.json)
* [`docs/iam/tf-optional.json`](../../docs/iam/tf-optional.json)
* [`docs/iam/testing.json`](../../docs/iam/testing.json)

> NOTE: Unlike the production `deployment/` modules, the smoke-test harness self-creates its own security groups and IAM roles/instance profiles/policies per test instance and does not expose the `EXISTING_*` bring-your-own-resource variables. It is intended for permissive dev/test accounts; run it in a sandbox account if your environment enforces restrictive IAM (for example, denying `ec2:CreateSecurityGroup` or `iam:CreateRole`/`iam:CreatePolicy`).

## Local development

You can run the harness locally (or from the dev container) against any existing/default VPC. The only hard requirements are `REGION`, a valid `SUBNET` with outbound internet and a `PROXY_AMI` (see [Prerequisites](#prerequisites)).

The local commands are:

```bash
cd image/smoke-tests
make test          # full apply + check + destroy lifecycle
# or individual stages:
make apply         # only run terraform apply
make check         # only run smoke-tests
make destroy       # only run terraform destroy
make clean         # clean up local artefacts
```

Each invocation drives `go test` against the smoke-test Terraform in [`terraform/`](terraform/), reading the inputs documented in [Prerequisites](#prerequisites) from `terraform/terraform.tfvars`.

### Development prerequisites

* AWS credentials with the IAM policies described above.
* [Terraform](https://www.terraform.io/) 1.2.9 (matches the dev container).
* [Go 1.26](https://go.dev/) or higher.
* [GNU Make](https://www.gnu.org/software/make/).
* OpenSSH client (`ssh`, `scp`), the [AWS CLI](https://docs.aws.amazon.com/cli/), and the [`session-manager-plugin`](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) (all preinstalled in the dev container).
* A KNFSD proxy AMI ID supplied directly via `PROXY_AMI`. The test source/client AMIs are always resolved from SSM based on `ARCH`; see [`terraform/variables.tf`](terraform/variables.tf).

> WARNING: The Terraform state is stored on your **local** machine. Do not remove this state until you have run `make destroy` so that you can clean up the resources that were created.

### Configure Terraform

Create `image/smoke-tests/terraform/terraform.tfvars` with the three required inputs:

```hcl
REGION    = "us-east-1"
SUBNET    = "subnet-xxxxxxxxxxxxxxxxx"
PROXY_AMI = "ami-xxxxxxxxxxxxxxxxx"
```

The `PREFIX` variable defaults to `knfsd-smoke`; the Go driver overrides it with a `knfsd-smoke-<random.UniqueID()>` value per run, so concurrent runs in the same account do not collide. The `knfsd` prefix is required: it places all created IAM, CloudFormation, and EventBridge resources under the `knfsd-*` ARN scope granted to the restricted IAM policy (`docs/iam/tf-required.json`). To target an `arm64` client, override `ARCH = "arm64"` and `INSTANCE_TYPE` to a Graviton-family type (e.g. `m7g.2xlarge`) in `terraform.tfvars`, and build the matching binary with `make test TARGET_ARCH=arm64`; the Terraform pre-flight checks reject architecture mismatches between `ARCH` and `INSTANCE_TYPE`.

### SSH connectivity

The harness reaches the test client keylessly: it targets the instance by ID (`client_instance_id` output), tunnels `ssh`/`scp` over SSM (`AWS-StartSSHSession` via `session-manager-plugin` as an inline `ProxyCommand`), and pushes a short-lived RSA-2048 key via EC2 Instance Connect immediately before connecting. No SSH key pair is created or stored, the connection never uses the private IP, and port 22 ingress is not required. The required permissions are in [`docs/iam/testing.json`](../../docs/iam/testing.json).

A single ephemeral key is pushed per run; SSH connection multiplexing (`ControlMaster`/`ControlPersist`) lets the `scp` and `ssh` share one SSM tunnel. The driver waits for the client's SSM agent to report `Online` (via `ssm:DescribeInstanceInformation`) before connecting, replacing a fixed sleep.

### Stage skipping

The smoke-test driver runs three stages in sequence within a single `go test` invocation: `apply` (provision TF infrastructure), `check` (run the validation block), and `destroy` (tear down TF resources). State is persisted between `go test` runs via terratest's `terraform/.test-data/` directory, which lets you split the stages across multiple invocations — useful when iterating on the check stage without re-paying the apply cost every time.

Each stage is gated by an environment variable. Setting the variable to **any non-empty value** tells the driver to skip that stage and move on; an unset variable (or one set to the empty string) lets the stage run normally:

| Variable       | When set, the driver skips...                               |
|----------------|-------------------------------------------------------------|
| `SKIP_apply`   | `terraform init` and `terraform apply`. Reuses prior state. |
| `SKIP_check`   | The validation block (`scp` + remote `go test`).            |
| `SKIP_destroy` | `terraform destroy`. Leaves infra up for inspection.        |

The `make apply` / `make check` / `make destroy` wrappers above set these for you — each target sets the other two `SKIP_*` variables to `true` and clears the one for the stage you want to run, so each invocation runs exactly one stage. Direct env-var use is rarely needed; reach for it only when driving `go test` outside `make` (e.g. from an IDE debugger), or for a non-standard combination such as `SKIP_destroy=true make test` (apply + check, leave infra up).

Typical iteration flow:

```bash
cd image/smoke-tests
make apply                # one-off: creates infra, persists .test-data/
# ... edit a Go assertion
make check                # re-runs only the check stage against the live infra
# ... edit again
make check
make destroy              # tear down infra when finished
make clean                # clean up local artefacts
```
