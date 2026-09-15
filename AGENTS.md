# AGENTS.md

Orientation for AI coding assistants and automation working in this repository.
Human contributors should start at [README.md](README.md) and
[docs/index.md](docs/index.md); this file gives an agent the context it cannot
infer from any single file, and draws a hard line around the commands that spend
money.

## 1. What this repository is

KNFSD File Cache is a **high-performance NFS caching proxy for AWS**. It mounts
NFS exports from a source filer (typically on-premises or an AWS managed file
system) and re-exports them to downstream NFS clients in a VPC, giving two cache
layers: the kernel page cache in RAM (L1) and FS-Cache/`cachefilesd` on local
NVMe (L2).

It is a **build-and-deploy toolkit, not an application**. There is no service to
run locally, no dev server, and no `main()` that represents the product. The
deliverables are:

1. An **AMI**, built by Packer, containing a custom Linux kernel with NFS
   patches, `nfs-kernel-server`, `cachefilesd`, and this project's agents.
2. **Terraform modules** that deploy an Auto Scaling group of instances from that
   AMI, plus traffic distribution, an FSID database, and a CloudWatch dashboard.

Nothing you change takes effect without one or both of those phases.

## 2. The two-phase model

```text
Phase 1 (Packer)                     Phase 2 (Terraform)
image/  --build--> AMI  ------------> deployment/  --apply--> running cluster
```

The single most important consequence: **`image/resources/startup/proxy-startup.sh`
lives inside the AMI.** `image/resources/scripts/10_build.sh` installs it to
`/usr/local/sbin/proxy-startup.sh`, and the launch-template user data in
`deployment/terraform-module-knfsd/compute.tf` executes it on every boot. Editing
that script has **no effect** until the AMI is rebuilt and the new AMI ID is
passed as `PROXY_AMI`. A `terraform apply` alone will not pick up the change.

Runtime configuration flows along a separate path that does *not* require an AMI
rebuild:

```text
Terraform variable (variables.tf)
  -> SSM SecureString at /knfsd/<CLUSTER_NAME>/<KEY>   (parameters.tf)
  -> load_parameters() on boot                         (proxy-startup.sh)
  -> get_parameter KEY
  -> sysctls / mount options / /etc/exports.d/knfsd.exports
  -> readiness reported via the knfsd-file-cache:status EC2 tag
```

`ENABLE_STATUS_CHECK` (implemented in `status.tf`) and the AWS Console status
column both read that tag. Status tagging is best-effort: a failed
`ec2:CreateTags` disables tagging for the rest of the boot but does not fail
startup.

## 3. Repository map

| Path                                                    | Owns                                                                                                                                             |
|---------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| `image/`                                                | Packer template (`knfsd.pkr.hcl`), build scripts (`resources/scripts/`), kernel patches, and the boot-time `resources/startup/proxy-startup.sh`  |
| `image/resources/knfsd-agent/`                          | Go: lightweight HTTP API exposing node information, FS-Cache usage and counters, plus a POST endpoint to drop caches                             |
| `image/resources/knfsd-metrics-agent/`                  | Go: OpenTelemetry collector with custom receivers (`nfsd`, `fscache`, `mounts`, `exports`, `connections`, `slab`, `oldestfile`, `fragmentation`) |
| `image/resources/knfsd-fsidd/`                          | Go: allocates cluster-consistent FSIDs via a DynamoDB table                                                                                      |
| `image/resources/filter-exports/`, `netapp-exports/`    | Go: export discovery and filtering helpers                                                                                                       |
| `image/smoke-tests/`                                    | Terratest end-to-end harness that provisions real AWS infrastructure                                                                             |
| `deployment/terraform-module-knfsd/`                    | The main Terraform module (the thing users consume)                                                                                              |
| `deployment/database/`                                  | DynamoDB FSID table module                                                                                                                       |
| `deployment/metrics/`                                   | CloudWatch dashboard module (`dashboard/dashboard.json`)                                                                                         |
| `deployment/vpc-endpoints/`                             | Optional PrivateLink endpoints for private-subnet deployments                                                                                    |
| `examples/`                                             | Six self-contained, copy-and-adapt Terraform configurations                                                                                      |
| `docs/`, `deployment/docs/`, `docs/tests/`, `tutorial/` | All prose documentation. `docs_dir` is the repository root, so these are also mkdocs site pages                                                  |
| `docs/iam/`                                             | Canonical IAM policies as committed JSON                                                                                                         |
| `mkdocs/`                                               | mkdocs theme assets and build hooks (`repo_links.py`, `copyright_year.py`, `cards.py`)                                                           |
| `.devcontainer/`                                        | `prod` (build and deploy only) and `dev` (full toolchain) containers, plus maintainer scripts                                                    |

There are **six independent Go modules**, each with its own `go.mod` and
`Makefile`. There is no Go workspace file; build and test each in its own
directory, or use the root `Makefile` aggregate targets.

## 4. The dev container is the toolchain

Almost every `Makefile` target assumes the tools installed by
`.devcontainer/dev`. On a bare host most are absent, and `make lint` fails on its
first target rather than reporting anything useful.

Tools the targets expect that are commonly missing outside the container: `go`,
`golangci-lint`, `shfmt`, `shellcheck`, `tflint`, `terraform`, `packer`,
`codespell`, `editorconfig-checker`, `black`, `mypy`, `pylint`, `checkov`,
`trivy`, `semgrep`, `mkdocs`, `pre-commit`, `iamlive`, `docker`.

Before running an aggregate target, check what is actually available rather than
assuming. Outside the container, prefer the narrow targets whose dependencies you
have confirmed, and say plainly in your summary which checks you could not run.
Do not install the missing toolchain onto the host to work around this; that is
what the container is for.

Some maintainer scripts in `.devcontainer/dev/` also rely on GNU userland.
`update-version.sh` and `generate-third-party-lic-file.sh` use `sed -i -r`, which
misbehaves with BSD `sed` on macOS. Run those inside the container.

## 5. Command safety

Scale caution to blast radius. This repository mixes free local checks with
commands that provision large EC2 instances in a real AWS account, in one
`Makefile`, with no visual distinction between them.

### Safe: local, free, no AWS calls

| Command                                      | Notes                                                                                                                                             |
|----------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| `make bats`                                  | BATS tests for `proxy-startup.sh`. Requires Docker: `image/resources/startup/run-tests.sh` builds a `linux/amd64` image and runs the suite inside |
| `make gotest`                                | `go test -cover -vet=all` across five Go modules. `image/smoke-tests` has no `gotest` target, only AWS-provisioning stages                        |
| `make golint`                                | `golangci-lint` across all six Go modules                                                                                                         |
| `make lic-scan`                              | Trivy license scan of the tree. Local and free, just slow                                                                                         |
| `make lint`                                  | `ec codespell shfmt shellcheck-sh shellcheck-bash shellcheck-bats black mypy pylint iam-size`                                                     |
| `make iam-size`                              | Checks each IAM policy fits the 6,144 non-whitespace-character AWS managed-policy limit. Only needs `python3`                                     |
| `make packer-fmt`, `make packer-val`         | Format and validate the Packer template                                                                                                           |
| `make tf-fmt`, `make tf-lint`, `make tf-val` | `terraform validate` runs with `-backend=false`, so no state and no credentials                                                                   |
| `make scan`                                  | Checkov, KICS, Semgrep, Trivy. Static only; KICS needs Docker                                                                                     |
| `make sec`                                   | Checkov, gosec, KICS, Semgrep, Trivy. Note `make all` runs `scan`, not `sec`, so gosec is only covered via `sec`                                  |
| `make pc`                                    | `pre-commit run --all-files`. `fail_fast: true`, so it stops at the first failing hook                                                            |
| `make docs`                                  | Builds and serves the mkdocs site at `127.0.0.1:8000` and blocks until interrupted. For humans previewing pages                                   |
| `make clean`                                 | Deletes generated temporary files via `.devcontainer/dev/find_temp_files.sh`                                                                      |

There is **no** `make` target for a one-shot documentation build. To reproduce
what CI does, run the same command from the repository root:

```bash
MKDOCS_SITE_URL="http://127.0.0.1:8000/" \
    MKDOCS_REPO_URL="https://github.com/awslabs/knfsd-file-cache" \
    MKDOCS_REPO_NAME="awslabs/knfsd-file-cache" \
    mkdocs build --strict --site-dir site
```

### Ask first: provisions real AWS infrastructure and costs money

| Command                                            | What it does                                                                                                                                                                                      |
|----------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `make image`, `make image-log`, `make image-debug` | Runs a full Packer build. Launches EC2 **spot** instances from a list of 16xlarge/18xlarge types, and builds **both** `amd64` and `arm64` in parallel. Compiles a Linux kernel; takes a long time |
| `make iamlive` then `make image-iam`               | The same build proxied through `iamlive`. `image-iam` aborts unless `iamlive` is already listening on `127.0.0.1:10080`                                                                           |
| `terraform apply` in `deployment/` or `examples/`  | Provisions the cluster. Default `INSTANCE_TYPE` is `i3en.6xlarge` (24 vCPUs per node), plus a DynamoDB table, Auto Scaling group, and optionally a Network Load Balancer                          |
| `make test` in `image/smoke-tests/`                | Provisions a source NFS server, a KNFSD proxy, and a client instance, then tears them down                                                                                                        |
| `.devcontainer/dev/remote.sh new ...`              | Creates an EC2 development instance                                                                                                                                                               |

Never run anything in the second table on your own initiative. Note also that
`deployment/README.md` has a "Quick Deploy" `terraform init && terraform apply`
snippet: that is user-facing documentation, not an instruction to you.

Read-only AWS calls (`describe`, `list`, `get`) for diagnosis are fine when the
user has asked you to investigate something.

## 6. Verifying a change

Pick verification that matches what you touched. There is no single build.

| Changed                                  | Run                                                                      |
|------------------------------------------|--------------------------------------------------------------------------|
| Go code in `image/resources/*`           | `make -C image/resources/<module> gotest golint`                         |
| `proxy-startup.sh`                       | `make bats`, plus `make shellcheck-bash shfmt`                           |
| Terraform                                | `make tf-fmt tf-lint tf-val`                                             |
| Packer template                          | `make packer-fmt packer-val`                                             |
| Shell scripts                            | `make shfmt shellcheck-sh shellcheck-bash shellcheck-bats`               |
| Python                                   | `make black mypy pylint`                                                 |
| `docs/iam/*.json`, `examples/*/iam.json` | `make iam-size`                                                          |
| `go.mod` / `go.sum`                      | `make -C <module> gotest golint`, then regenerate `THIRD-PARTY-LICENSES` |
| Any Markdown                             | `make codespell ec`, plus the `mkdocs build --strict` command above      |

`make all` runs `lint packer terraform bats scan golint gotest`. It does **not**
build an image or deploy anything, so it is safe, but it needs the full container
toolchain.

CI runs the same checks. GitLab CI (`.gitlab-ci-aws.yml`) covers the `lint` suite,
`iam-size`, BATS, Terraform and Packer format/validate, per-module
`golangci-lint`, `go test`, `govulncheck`, cross-arch `go build`, `gosec`, the
Checkov, KICS, Semgrep, and Trivy scanners, Renovate dependency updates, and a
`pages` job that publishes the site. GitHub Actions runs CodeQL and publishes the
site from `main`. Passing the local targets above is a good predictor of a green
pipeline, and since you never push, it is the only signal you get.

## 7. Cross-file change checklists

These changes span files that are not discoverable from any one of them, so a
partial change looks correct locally and fails in CI, at `terraform plan`, or
silently at runtime.

### 7.1 Add a Terraform variable that changes proxy behaviour

The most common multi-file change and the easiest to get wrong. The value has to
travel from Terraform, through SSM Parameter Store, into the boot-time script.

1. **`deployment/terraform-module-knfsd/variables.tf`** declares it with
   `description`, `type`, `nullable`, and `default`. The description is the source
   of truth and gets copied into `parameters.tf`, so use the house style:
   `"(Optional) <what it does>. Default: \"<value>\"."`
2. **`validations.tf`** holds anything needing AWS lookups or cross-variable
   logic, as a `data` source with `lifecycle { postcondition { ... } }`. Simple
   bounds go in a `validation` block in `variables.tf` instead. Include the
   `# tflint-ignore: terraform_unused_declarations` comment, since these data
   sources are intentionally unreferenced.
3. **`parameters.tf`** needs **two separate edits**: the
   `aws_ssm_parameter.settings` `for_each` map, and `locals.descriptions`. The
   keys must match exactly, because `parameters.tf` looks up
   `local.descriptions[each.key]` for every entry. For a `list(string)`, join it
   with `join("\n", var.MY_LIST)`; the startup script splits on newlines.
4. **Regenerate the descriptions block, do not hand-write it:**

   ```bash
   cd .devcontainer/dev
   ./parse-variable-descriptions.sh
   ```

   Paste the output over the existing block. This keeps the SSM parameter
   descriptions in sync with the variable descriptions, which is otherwise a
   silent drift.
5. **`image/resources/startup/proxy-startup.sh`** reads it with
   `get_parameter MY_VARIABLE`. All parameters are loaded once into the
   `PARAMETERS` associative array by `load_parameters()`, so `get_parameter` is a
   lookup, not an API call, and is cheap to call repeatedly.
6. **`image/resources/startup/tests/*.bats`** gains coverage in
   `configure-kernel.bats`, `configure-nfs.bats`, `configure-fscache.bats`,
   `export-auto-detect.bats`, or a new file. Shared helpers live in
   `helpers.bats` and `common.bash`.
7. **`deployment/README.md`** gains a row in the correct table. Tables are grouped
   by concern (Network, Export, KNFSD Proxy, Cachefilesd, Mount Options, NFS
   Kernel Client/Server Options, Export Options, FSID Database, Autoscaling) with
   columns `Variable | Description | Required | Default`.
8. **`examples/*/variables.tf`** and the example's module block, if the variable
   should be surfaced.
9. **`CHANGELOG.md`** gains a bullet under `## (Unreleased)`, plus the AMI-rebuild
   marker if you touched `proxy-startup.sh` in step 5.

Gotchas:

* **`proxy-startup.sh` is baked into the AMI.** Adding a *parameter* alone needs
  no rebuild, but consuming it does.
* **Empty strings.** SSM will not store an empty value, so `parameters.tf` writes
  the literal two-character string `""` and `load_parameters()` converts it back.
  Do not add your own empty-string handling.
* **Parameters are `SecureString`** at `/knfsd/<CLUSTER_NAME>/<KEY>`, read with
  `get-parameters-by-path --recursive --with-decryption`.
* **No IAM change is needed for a new key.** The instance role's
  `ssm:GetParametersByPath` is scoped to `/knfsd/<CLUSTER_NAME>` and
  `/knfsd/<CLUSTER_NAME>/*`.
* **Startup fails loudly if zero parameters come back.** That is deliberate; it
  catches a `CLUSTER_NAME` mismatch rather than booting with silent defaults.

Verify with `make tf-fmt tf-lint tf-val bats shellcheck-bash shfmt codespell ec`.

### 7.2 Add a Terraform variable that only affects AWS resources

Shorter than 7.1: variables that shape infrastructure rather than in-instance
behaviour never reach SSM. Examples are `INSTANCE_TYPE`, `ROOT_DISK_SIZE`,
`EBS_KMS_KEY_ID`, and `TRAFFIC_MODE`.

1. `variables.tf` declares it.
2. `validations.tf` validates it.
3. The `.tf` file that consumes it (`compute.tf`, `autoscaling.tf`,
   `loadbalancing.tf`, `vpc.tf`, `iam.tf`, `status.tf`, or `main.tf`).
4. `outputs.tf`, if it changes what the module returns.
5. `deployment/README.md`, the variable table, and the Outputs table if step 4
   applied.
6. `examples/*/variables.tf`, if surfaced.
7. `CHANGELOG.md`.

**Do not** add it to `parameters.tf`. Nothing on the instance reads it, and it
would appear in the startup log as a confusing unused parameter. No AMI rebuild is
needed.

Verify with `make tf-fmt tf-lint tf-val scan-checkov scan-kics scan-trivy`.

### 7.3 Add or rename a documentation page

`mkdocs.yml` sets `docs_dir: "."`, so the repository root *is* the docs source and
every Markdown file is both a repo file and a site page. A new page needs
registering in more than one index.

1. **The page itself**, in `docs/`, `deployment/docs/`, or beside the code it
   documents. The Go modules keep their docs next to the source.
2. **`mkdocs.yml`** gains a `nav` entry under the right top-level section (Home,
   Build & Deploy, Reference, User Guide, Tutorial, Examples, Test Plans,
   Developer, Resources, Other). A page absent from `nav` still builds but is
   unreachable from the site navigation.
3. **`docs/index.md`** gains an entry in the matching list. This is the
   repo-browser index and is maintained separately from `mkdocs.yml`.
4. **`README.md`**, only if it belongs in the landing-page card grid.
5. **`CHANGELOG.md`**, for a substantive new page.

`README.md`, `examples/README.md`, and `docs/resources.md` contain blocks
delimited by `<!-- grid-cards:start -->` and `<!-- grid-cards:end -->`, or
`<!-- video-cards:start -->` and `<!-- video-cards:end -->`. These are portable
Markdown in the repository, converted into Material card grids at build time by
`mkdocs/hooks/cards.py`. The shape matters:

```markdown
<!-- grid-cards:start -->
* **Card Title**<br> <!-- icon: material-rocket-launch-outline -->
  The card description on the following line.
  * [A link in the card footer](path/to/page.md)
<!-- grid-cards:end -->
```

The icon goes in an HTML comment so the repo browser does not show a literal
`:material-...:` shortcode. Do not hand-write the `<div class="grid cards">`
HTML; that is what the hook produces, and writing it directly breaks rendering on
GitHub and GitLab.

`mkdocs/hooks/repo_links.py` rewrites links that point at repo-root files a static
site cannot host, such as extensionless files like `Makefile` and `LICENSE`, and
dotfiles like `.tflint.hcl`, into absolute `repo_url` links at build time. Link to
them with ordinary relative paths such as `../Makefile` and let the hook handle it.

Verify with the `mkdocs build --strict` command in section 5, plus
`make codespell ec`. `validation.links.anchors` is `warn` and `--strict` promotes
warnings to failures, so a broken anchor fails locally exactly as it fails CI.

### 7.4 Add a metric

Metrics originate in a custom OpenTelemetry receiver, are shaped by YAML config,
and are visualised by a committed CloudWatch dashboard JSON.

1. **`image/resources/knfsd-metrics-agent/internal/<receiver>/`** holds the
   receiver. Existing receivers are `nfsd`, `fscache`, `mounts`, `exports`,
   `connections`, `slab`, `oldestfile`, and `fragmentation`.
2. **`internal/<receiver>/documentation.md`** is the generated metric reference.
   Each receiver has one, and each is listed in both `mkdocs.yml` and
   `docs/index.md`.
3. **The OTEL YAML config** in `image/resources/knfsd-metrics-agent/config/`:
   `common.yaml` for anything shared, `proxy.yaml` or `client.yaml` for
   role-specific collection. Leave `custom.yaml` empty; it is a deliberate
   placeholder that user start-up scripts replace to reconfigure the agent without
   rebuilding the image. See `cmd/gen-overrides/README.md` before editing
   generated output by hand.
4. **`image/resources/cloudwatch-agent/amazon-cloudwatch-agent.json`**, only for
   host-level metrics collected by the CloudWatch agent rather than the OTEL agent.
5. **`deployment/metrics/dashboard/dashboard.json`** holds the widgets.
6. **`deployment/metrics/variables.tf`** needs its `VERSION` default bumped.
   This is the dashboard version and is **independent of the project release
   version**; `update-version.sh` does not touch it.
7. **`deployment/docs/metrics.md`** and **`deployment/metrics/README.md`** hold the
   metric reference tables.
8. **`CHANGELOG.md`** gains the metric, plus
   `Updated KNFSD Monitoring Dashboard to \`v<N>\`.` matching step 6. If the new
   dashboard needs a newer agent, add a `> BREAKING CHANGES:` note stating the
   minimum compatible release, as previous versions have.

Gotchas:

* Metric namespaces are `/knfsd/logs`, `/knfsd/ec2`, and `/knfsd/metrics`, all
  with a leading slash.
* `dashboard.json` is deliberately excluded from the `pretty-format-json`
  pre-commit hook. Do not reformat it.
* Dashboards use CloudWatch `SEARCH` expressions wrapped in `REMOVE_EMPTY` to
  suppress `NaN` series, and explicit `id` values on metric-math expressions to
  keep label ordering deterministic. Follow the surrounding widgets.
* A new metric requires an AMI rebuild to reach instances, since the agent and its
  config are baked in.

Verify with `make -C image/resources/knfsd-metrics-agent gotest golint`, then
`make codespell ec` and
`python3 -m json.tool deployment/metrics/dashboard/dashboard.json > /dev/null`.

### 7.5 Add an IAM permission

Policies are committed JSON, grouped by which phase or feature needs them.

| File                                        | Scope                                      |
|---------------------------------------------|--------------------------------------------|
| `docs/iam/packer.json`                      | The identity running Packer                |
| `docs/iam/packer-instance-profile.json`     | The Packer build instance's own role       |
| `docs/iam/tf-required.json`                 | Always needed to deploy                    |
| `docs/iam/tf-optional.json`                 | Feature-gated deploy permissions           |
| `docs/iam/vpc-endpoints.json`               | The standalone `vpc-endpoints` module      |
| `docs/iam/testing.json`                     | The `image/smoke-tests` harness            |
| `docs/iam/remote-ssh.json`                  | The developer identity running `remote.sh` |
| `docs/iam/remote-ssh-instance-profile.json` | The development instance's own role        |
| `examples/*/iam.json`                       | Per-example policies                       |

1. Consult [security-considerations.md](docs/security-considerations.md) for the
   security architecture and controls for KNFSD File Cache deployments on AWS.
2. The relevant policy file, added to an existing `Sid` or a new one. `Sid` values
   are named descriptively, such as `KnfsdPackerBuild` and
   `KnfsdPackerSsmChannels`.
3. **`docs/iam.md`**, the reference tables mapping `Sid` values to purpose, and the
   "Deploying under restrictive IAM" section if the change interacts with
   `EXISTING_*` variables.
4. **The Terraform that needs it**: `terraform-module-knfsd/iam.tf`,
   `database/main.tf`, or `modules/dns_round_robin/lambda.tf`.
5. **`CHANGELOG.md`**.

Gotchas:

* **6,144-character limit.** `make iam-size` enforces the AWS customer-managed
  policy limit against `docs/iam/*.json` and `examples/*/iam.json`, counting
  non-whitespace characters. It runs in pre-commit and in CI. If you are over,
  scope resources more tightly rather than deleting a needed action.
* Prefer resource-scoped ARNs over `"*"`. Recent changes have moved that way
  deliberately, for example scoping `ssm:GetParametersByPath` to the deployment's
  own parameter hierarchy.
* Service-linked roles are **not** created by Terraform. The module does a
  read-only `iam:ListRoles` pre-flight check and fails at plan time with the
  `aws iam create-service-linked-role` command to run. Do not reintroduce
  `iam:CreateServiceLinkedRole`.
* Weigh every new create-permission against the `EXISTING_*` escape hatches
  (`EXISTING_SECURITY_GROUP_ID`, `EXISTING_INSTANCE_PROFILE_NAME`,
  `EXISTING_LAMBDA_ROLE_ARN`, `FSID_DATABASE_IAM_POLICY`), which let users deploy
  without it.

Verify with `make iam-size tf-fmt tf-lint tf-val scan-checkov scan-trivy`.

### 7.6 Change the Packer build

Anything in `image/` other than the Terraform-facing docs changes AMI contents.

1. **`image/knfsd.pkr.hcl`** is the template. Note there are **two** builder
   blocks, `amd64` and `arm64`, that build in parallel and largely mirror each
   other. A change to one usually needs the same change to the other.
2. **`image/variables.pkr.hcl`** holds new Packer variables, with validation.
3. **`image/resources/scripts/`** holds `10_build.sh` (main build),
   `20_post_build.sh`, and `30_finalize.sh`.
4. **`image/resources/patches/`** holds patches applied with `quilt`, in two
   subdirectories that are applied at different points and behave differently:
   `cachefilesd/` is imported unconditionally while building the `cachefilesd`
   package, whereas `kernel/` is applied during `build_kernel()` behind a glob
   guard, so an **empty or missing `kernel/` directory is silently skipped**.
   Adding the first patch to a new subdirectory therefore requires creating the
   directory itself, or the patch is ignored with no error. Excluded from
   pre-commit via the `^(.*\.patch$|.*mountstats$)` pattern, so they are not
   reformatted.
5. **`image/README.md`** is the Packer variable reference.
6. **`docs/iam/packer.json`**, if the build calls a new AWS API.
7. **`CHANGELOG.md`**, with `Packer:` prefixed bullets matching the existing style,
   plus the AMI-rebuild marker.

Gotchas:

* Network calls in build scripts must retry. `curl` invocations use `--retry` and
  `--retry-delay`, `git clone` goes through the `git_clone` wrapper, and `snap`
  goes through `snap_refresh`. Follow those patterns for anything new.
* Do not add `expect_disconnect` to the script provisioners. The only occurrence in
  the template is on the dedicated reboot provisioner after `10_build.sh`; that
  separation is deliberate, so a lost connection during a build script, a spot
  reclaim for instance, fails the build instead of silently truncating it.
* The build runs on EC2 spot with a list of candidate instance types and
  `price-capacity-optimized` allocation. Do not narrow that list without reason; it
  exists to find capacity.
* `/mnt/build` and `/tmp` are `tmpfs`. Large intermediate artifacts consume RAM,
  not disk.

Verify with `make packer-fmt packer-val shellcheck-bash shfmt`. Validating the
template does **not** build an image; an actual `make image` run launches large EC2
instances and compiles a kernel, so get explicit approval first.

### 7.7 Update Go dependencies

Six Go modules update independently, and five of them are compiled into the AMI by
`10_build.sh`, so a dependency bump is an AMI-contents change with a side effect on
the license file. Renovate automates routine bumps in GitLab CI; this is for making
the same change by hand.

1. **The module's `go.mod` and `go.sum`**, updated from the module directory with
   `make goget` (`go get -t -u ./...` followed by `go mod tidy`). Run `make goget`
   from the repository root to update all six modules at once, or `make gotidy`
   alone after editing a `go.mod` by hand.
2. **`THIRD-PARTY-LICENSES`**, regenerated and never hand-edited:

   ```bash
   cd .devcontainer/dev
   ./generate-third-party-lic-file.sh
   ```

   The script reruns the Trivy license scan and rewrites the file with a fresh
   header. It uses GNU `sed -i`, so run it inside the dev container.
3. **`.trivyignore.yaml`**, only if a new or upgraded dependency introduces a
   license Trivy flags. The `licenses:` block is an allowlist of acceptable license
   IDs; extending it is a conscious decision about license acceptability, not a
   mechanical step. The same file also holds `misconfigurations:` and
   `vulnerabilities:` suppressions.
4. **`CHANGELOG.md`**, a bullet for any notable bump, plus the AMI-rebuild marker if
   the module is one of the five baked into the AMI, which is everything except
   `image/smoke-tests`.

Gotchas:

* `image/smoke-tests` dependencies never reach the AMI; the other five modules'
  binaries are installed into it by `10_build.sh`.
* The Go toolchain itself is pinned separately. `10_build.sh` downloads a fixed
  release, `go1.27.1` at the time of writing, and `KNFSD_GOLANG_VERSION` in
  `.gitlab-ci-aws.yml` must match. `goget` changes neither.
* There is no Go workspace file, so `go get` and `go mod tidy` must run per module.
  The root aggregate targets already handle the loop.

Verify with `make gotest golint lic-scan`.

### 7.8 Bump the release version

Never hand-edit version strings. The version appears in module `source` refs
throughout the docs, in the Packer template, and in the issue templates.

```bash
cd .devcontainer/dev
./update-version.sh <OLD> <NEW>
```

A leading `v` is stripped, so either form works. What the script rewrites:

* `?ref=vX.Y.Z` in every `source = "github.com/awslabs/knfsd-file-cache/..."`
  across `*.tf`, `*.pkr.hcl`, and `*.md`.
* Standalone occurrences of the old version string in those same files, including
  `locals.version` in `image/knfsd.pkr.hcl`, which names the AMI and sets the
  `knfsd-file-cache:version` tag.
* `VERSION="<old>"` assignments anywhere in the tree.
* The `placeholder:` value in `.github/ISSUE_TEMPLATE/*.yml`, re-adding the `v`.

What it deliberately does not touch:

* **`CHANGELOG.md`**, excluded by design because it records history. Rename the
  `## (Unreleased)` heading to the new version and date by hand.
* **`deployment/metrics/variables.tf`'s `VERSION`**, the dashboard version, bumped
  independently (see 7.4).

Gotchas: run it **inside the dev container**, because it uses `sed -i -r`. Then
confirm no stray references remain:

```bash
grep -rn "<OLD>" --include='*.tf' --include='*.md' --include='*.hcl' . \
    | grep -v CHANGELOG
```

Verify with `make tf-fmt tf-val packer-val codespell ec`.

## 8. Solution usage tracking: do not remove

Four Terraform modules each declare an `aws_cloudformation_stack` whose template
contains nothing but an empty `AWS::CloudFormation::WaitConditionHandle`, and whose
`Description` carries the AWS Solution ID `(SO9129)` and the version. Every one is
preceded by the same comment:

```terraform
# this solution collects anonymous operational metrics to help AWS improve the quality of features of the solution
```

| File                                        | Resource                | Stack name                       |
|---------------------------------------------|-------------------------|----------------------------------|
| `deployment/terraform-module-knfsd/main.tf` | `metrics_knfsd`         | `${local.name}-metrics-knfsd`    |
| `deployment/database/main.tf`               | `metrics_database`      | `${local.name}-metrics-database` |
| `deployment/metrics/main.tf`                | `metrics_dashboard`     | `knfsd-metrics-dashboard`        |
| `deployment/vpc-endpoints/main.tf`          | `metrics_vpc_endpoints` | `knfsd-metrics-vpc-endpoints`    |

This is how AWS tracks adoption of this Solutions Guidance. The stacks deploy no
functional infrastructure, create nothing billable, and send no customer data; the
solution ID and version in the description are the entire signal. That is exactly why
they look like dead code to a linter, a reviewer, or a refactoring pass, and they must
survive all three.

**Do not remove, rename, consolidate, or make these resources conditional**, and do not
delete the comment above them. In particular:

* Do not merge the four into one shared stack or a helper module. Each module is
  independently consumable, so each carries its own.
* Keep `on_failure = "DO_NOTHING"`, which ensures a CloudFormation failure never fails a
  deployment.
* Keep the `(SO9129)` prefix and the `v${var.VERSION}` suffix in `Description` as
  written. `update-version.sh` (7.8) keeps three of them current; `deployment/metrics`
  intentionally interpolates the dashboard version instead (7.4).
* The required `cloudformation:*` permissions live in the `KnfsdCloudFormation` Sid of
  `docs/iam/tf-required.json` and `KnfsdVpcEndpointsCloudFormation` in
  `docs/iam/vpc-endpoints.json`. They are not optional (7.5).

Change any of this only when the user asks for it explicitly, never as a cleanup,
cost, or simplification improvement of your own.

## 9. Conventions

**Commits.** [Conventional Commits](https://www.conventionalcommits.org/), enforced
at the `commit-msg` stage by `conventional-pre-commit`. Allowed types are `feat`,
`fix`, `ci`, `chore`, `docs`, `build`, `style`, `refactor`, `perf`, `test`, and
`debug`. Build before committing. Commit locally and often; **never push**, that is
the maintainer's action.

**CHANGELOG.** Every user-visible change gets a bullet under the `## (Unreleased)`
heading at the top of `CHANGELOG.md`. Two markers matter:

* `> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.` is required whenever AMI
  contents change, including any edit to `proxy-startup.sh`.
* `> EXPERIMENTAL: ...` is for features explicitly subject to change.

**Formatting.** `.editorconfig` is authoritative and `editorconfig-checker` runs in
pre-commit and CI. Shell, Go, and `Makefile` files use **tabs**; Terraform, YAML,
JSON, HCL, Markdown, and Python use **spaces**. `.editorconfig` also carries the
`shfmt` settings (`binary_next_line`, `switch_case_indent`, `space_redirects`,
`keep_padding`), so run `make shfmt` rather than reformatting by hand. In shell
scripts, put a single space before a redirect to `/dev/null`, as in `2> /dev/null`.

**Terraform and language versions.** Terraform is pinned to v1.2.9 in CI, so keep
Terraform v1.2 compatible. Python is 3.14 (`black --target-version py314`) and Go
is 1.27.

**Documentation prose.** Fence every code block with a language. Keep tables padded
to column width, matching the surrounding file. Do not use em dashes.

**Security.** IAM policies are committed JSON under `docs/iam/` and are treated as
least-privilege reference material. Adding a permission means editing the policy
file *and* keeping it under the size limit. Never add credentials, account IDs, or
ARNs of real accounts to the repository; `gitleaks` and `detect-aws-credentials`
run in pre-commit.

## 10. Vocabulary

Terms used throughout the code and docs without definition:

* **KNFSD** is this solution as a whole: the kernel NFS server used as a caching
  re-export proxy.
* **Re-export** is mounting an NFS export from a source filer and serving it out
  again over NFS to other clients. The core mechanism.
* **L1 / L2 cache** are the kernel page cache in RAM, and FS-Cache on local NVMe.
* **FS-Cache / `cachefilesd`** are the Linux kernel facility and daemon that back
  the on-disk L2 cache, mounted at `/var/cache/fscache`.
* **Extent size hint** is the XFS allocation hint set by `CACHEFILESD_EXTSIZE`
  (MiB; `0`, `4`, `8`, or `16`, where `0` disables it). It pads each allocation so
  the cache's backing files stay in few large extents, because `SEEK_HOLE` in the
  `cachefiles` read path is a linear scan of the extent list. It is **persistent
  directory inode metadata, not a mount option**, so `proxy-startup.sh` re-applies
  it with `xfs_io -c "extsize -D"` on every boot, and it only affects allocations
  made after it is set. The padding is reported as **unwritten extents**, which is
  what the `fragmentation` receiver measures. See
  [known-issues.md](docs/known-issues.md).
* **FSID** is the filesystem identifier `mountd` assigns per export. All nodes in a
  cluster must agree, or a client that moves between nodes sees I/O errors. Hence
  `FSID_MODE`: `static`, `local` (sqlite, single node only), or `external`
  (DynamoDB via `knfsd-fsidd`; the recommended and default mode).
* **Fanout** is a two-tier topology where a tier-1 proxy fronts the source filer and
  a tier-2 cluster fronts tier 1. Tier 1 must be substantially larger than a tier-2
  node, and it requires `ENABLE_STATUS_CHECK = true`.
* **Traffic mode** is how clients reach nodes: `dns_round_robin` (recommended),
  `loadbalancer` (NLB), or `none` (bring your own).
* **Auto re-export** is `AUTO_REEXPORT`, which adds `crossmnt` and picks up nested
  mounts automatically. Requires an FSID mode of `local` or `external`.
* **ENA-X** is ENA Express (SRD). It raises single-flow bandwidth from 5 to 25 Gbps
  within an Availability Zone, is enabled automatically on supporting EC2 instance
  types, and falls back silently when unsupported. Both endpoints of a path must
  have it enabled.
* **`nconnect`** is the number of TCP connections from proxy to source filer.
* **EIC endpoint** is an EC2 Instance Connect Endpoint, one of two ways the
  developer tooling tunnels SSH into a private subnet. The other is SSM Session
  Manager.

## 11. When this solution fits, and when it does not

Users and agents both ask "should we use KNFSD here?" The README makes the positive
case; these are the disqualifiers.

**Good fit:** read-heavy HPC and burst-compute workloads where many clients in AWS
repeatedly read a largely static dataset held on a filer that is remote,
bandwidth-constrained, or expensive to hit directly. Rendering, EDA, genomics,
simulation, HPC, and CI fleets pulling shared assets or toolchains.

**Poor fit, or needs care:**

* **FAQs, Known Issues, and Caveats.** See [faq.md](docs/faq.md),
  [known-issues.md](docs/known-issues.md), [README.md](deployment/README.md),
  [check-startup.md](docs/check-startup.md), and
  [nfs-client-setup.md](docs/nfs-client-setup.md).
* **FileHandle size limit.** NFS protocol limits the size of a file handle that
  can be re-exported. Amazon EFS or S3-Files are not supported as the source filer.
* **Write-heavy workloads.** This is a read cache. Writes pass through and gain
  nothing, unless they are immediately read again.
* **Workloads needing strong cache coherency.** The attribute-cache defaults
  (`ACREGMIN`, `ACREGMAX`, `ACDIRMIN`, and `ACDIRMAX` all `600` seconds) trade
  freshness for throughput, so a client can see stale metadata for up to ten
  minutes. Lower `ACDIRMAX` to improve `readdir` freshness at the cost of more
  metadata traffic to the source.
* **Cost-sensitive deployments.** The default node is an `i3en.6xlarge`. Sizing down
  loses NVMe capacity for the L2 cache, and network bandwidth. Graviton (ARM) EC2
  instances are supported such as `im4gn.8xlarge` and provide superior
  cost-performance for these use cases.
* **Datasets smaller than client RAM,** or accessed once. The cache never pays for
  itself.
* **Exports whose paths collide with local symlinks**, such as `/bin`, `/lib`, and
  `/sbin`. Startup fails with `Cannot mount <host>:/bin because /bin matches a
  symlink`; remap the export to a different path, as in `10.0.0.2;/bin;/binaries`,
  or exclude it. See the Caveats section of `deployment/README.md`.

## 12. Where to look first

| Question                                             | File                                                                             |
|------------------------------------------------------|----------------------------------------------------------------------------------|
| What does this solution do, and where is everything? | [README.md](README.md), [docs/index.md](docs/index.md)                           |
| What changed recently, and what breaks?              | [CHANGELOG.md](CHANGELOG.md)                                                     |
| Every Terraform variable and output                  | [deployment/README.md](deployment/README.md)                                     |
| Every Packer variable                                | [image/README.md](image/README.md)                                               |
| What must exist before deploying?                    | [deployment/docs/prerequisites.md](deployment/docs/prerequisites.md)             |
| IAM permissions, per phase and per feature           | [docs/iam.md](docs/iam.md), [docs/iam/](docs/iam/)                               |
| Why a symptom happens?                               | [docs/known-issues.md](docs/known-issues.md), [docs/faq.md](docs/faq.md)         |
| How to confirm a proxy came up?                      | [docs/check-startup.md](docs/check-startup.md)                                   |
| Local development environment                        | [docs/developer.md](docs/developer.md)                                           |
| Which check runs where, and why?                     | [docs/pre-commit.md](docs/pre-commit.md), [docs/gitlab-ci.md](docs/gitlab-ci.md) |

## 13. This file

`AGENTS.md` is tooling documentation and is excluded from the published mkdocs site
via `exclude_docs` in `mkdocs.yml`. It is the single source of truth for agent
guidance in this repository.
