# Pre-commit System

> NOTE: You do not need to follow these instructions to create the image & deploy the knfsd-file-cache solution on AWS. These instructions are for developers who want to contribute to the project.

The KNFSD File Cache project utilizes a comprehensive pre-commit framework to ensure code quality, consistency, and security before changes are committed to the repository. This system automates the execution of multiple code quality tools and formatters across different languages and file types.

The pre-commit system integrates seamlessly with the development workflow and can be invoked through convenient `make` targets for both automated and manual validation.

## Overview

The pre-commit system is built around industry-standard tools that validate:

- **Code formatting and style** across multiple languages (Go, Python, Shell, HCL, YAML, JSON)
- **Spelling and grammar** in documentation and comments
- **Security vulnerabilities** and coding best practices
- **Infrastructure as Code** standards for Terraform and Packer
- **Git commit message** conventions

## Quick Start

### Installing Pre-commit

To enable pre-commit hooks for all git commits locally:

```bash
# Install pre-commit hooks (one-time setup)
pre-commit install

# Install commit message hooks for conventional commits
pre-commit install --hook-type commit-msg
```

### Running Pre-commit Manually

You can run pre-commit checks manually using `make` targets:

```bash
# Run all pre-commit checks (aliased as 'pc' for convenience)
make pre-commit
make precommit
make pc
```

### Updating Pre-commit Tools

To update all pre-commit tools to their latest versions:

```bash
# Update all repository versions in .pre-commit-config.yaml
# (aliased as 'precommit-update', 'pc-update' and 'autoupdate')
make pre-commit-update
make pc-update
make autoupdate

# Update the Go dependencies of every Go project
make goget

# Clean and update pre-commit cache
pre-commit clean
pre-commit install
```

## Make Targets Reference

### Main Makefile Commands

The root [`Makefile`](../Makefile) provides the following targets:

| Command          | Purpose                          | Tools Used                                                                             | Files Created                     |
|------------------|----------------------------------|----------------------------------------------------------------------------------------|-----------------------------------|
| `make all`       | Run complete validation suite    | All linting, Packer, Terraform, BATS, security scanners, Go tools                      | Various cache and build artifacts |
| `make pc`        | Run all pre-commit hooks         | [pre-commit](https://pre-commit.com/)                                                  | -                                 |
| `make pc-update` | Update pinned hook revisions     | [pre-commit](https://pre-commit.com/)                                                  | -                                 |
| `make lint`      | Run all linting tools            | EditorConfig, Codespell, shfmt, ShellCheck, Black, MyPy, Pylint, IAM policy size check | -                                 |
| `make sec`       | Run every security scanner       | Checkov, Gosec, KICS, Semgrep, Trivy                                                   | Scanner caches                    |
| `make docs`      | Serve the documentation locally  | [MkDocs](https://www.mkdocs.org/)                                                      | -                                 |
| `make clean`     | Delete generated temporary files | [`find_temp_files.sh`](../.devcontainer/dev/find_temp_files.sh)                        | -                                 |

`make all` runs `lint`, `packer`, `terraform`, `bats`, `scan`, `golint` and `gotest`.

### Image Build Commands

These targets are not part of the pre-commit flow, but they live in the same root
[`Makefile`](../Makefile) and are listed here for completeness:

| Command            | Purpose                                                              | Files Created  |
|--------------------|----------------------------------------------------------------------|----------------|
| `make image`       | Build the knfsd AMI with Packer                                      | -              |
| `make image-debug` | Build the AMI with `packer build -debug` and Packer logging enabled  | `packer.log`   |
| `make image-log`   | Build the AMI with Packer logging enabled                            | `packer.log`   |
| `make iamlive`     | Start [iamlive](https://github.com/iann0036/iamlive) in proxy mode   | `iamlive.json` |
| `make image-iam`   | Build the AMI through the `iamlive` proxy to capture the IAM actions | `iamlive.json` |

> NOTE: `make image-iam` requires `make iamlive` to be running in another terminal.

### Code Quality and Formatting

| Command                | Purpose                                    | Tool                                                                                 | Configuration                       | Reference                                                                                |
|------------------------|--------------------------------------------|--------------------------------------------------------------------------------------|-------------------------------------|------------------------------------------------------------------------------------------|
| `make ec`              | Validate EditorConfig formatting           | [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker) | [`.editorconfig`](../.editorconfig) | [EditorConfig Documentation](https://editorconfig.org/)                                  |
| `make codespell`       | Check spelling in code and docs            | [Codespell](https://github.com/codespell-project/codespell)                          | [`.codespellrc`](../.codespellrc)   | [Codespell Documentation](https://github.com/codespell-project/codespell)                |
| `make shfmt`           | Report shell script formatting differences | [shfmt](https://github.com/mvdan/sh)                                                 | [`.editorconfig`](../.editorconfig) | [shfmt Documentation](https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd)     |
| `make shellcheck-sh`   | Lint tracked `*.sh` scripts                | [ShellCheck](https://github.com/koalaman/shellcheck)                                 | [`.shellcheckrc`](../.shellcheckrc) | [ShellCheck Documentation](https://www.shellcheck.net/)                                  |
| `make shellcheck-bash` | Lint tracked `*.bash` scripts              | [ShellCheck](https://github.com/koalaman/shellcheck)                                 | [`.shellcheckrc`](../.shellcheckrc) | [ShellCheck Documentation](https://www.shellcheck.net/)                                  |
| `make shellcheck-bats` | Lint tracked `*.bats` test files           | [ShellCheck](https://github.com/koalaman/shellcheck)                                 | [`.shellcheckrc`](../.shellcheckrc) | [ShellCheck Documentation](https://www.shellcheck.net/)                                  |
| `make black`           | Format Python code                         | [Black](https://github.com/psf/black)                                                | `py314` target version              | [Black Documentation](https://black.readthedocs.io/)                                     |
| `make mypy`            | Type check Python code                     | [MyPy](https://github.com/python/mypy)                                               | Built-in configuration              | [MyPy Documentation](https://mypy.readthedocs.io/)                                       |
| `make pylint`          | Lint Python code                           | [Pylint](https://github.com/pylint-dev/pylint)                                       | Built-in configuration              | [Pylint Documentation](https://pylint.pycqa.org/)                                        |
| `make iam-size`        | Verify IAM policy JSON size limits         | Embedded Python script                                                               | 6,144 character AWS limit           | [IAM Quotas](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html) |

The three `shellcheck-*` targets split the scan by file extension so that each file type is checked
with the correct dialect. All of them run with `--severity=style`.

`make iam-size` validates that each `docs/iam/*.json` and `examples/*/iam.json` file is valid JSON
and, ignoring whitespace, fits inside the AWS customer managed policy character limit.

### Infrastructure as Code

| Command           | Aliases     | Purpose                   | Tool                                                  | Configuration                   | Reference                                                                                     |
|-------------------|-------------|---------------------------|-------------------------------------------------------|---------------------------------|-----------------------------------------------------------------------------------------------|
| `make packer-fmt` | `packer`    | Format Packer HCL files   | [Packer](https://www.packer.io/)                      | Built-in formatter              | [Packer fmt Command](https://developer.hashicorp.com/packer/docs/commands/fmt)                |
| `make packer-val` | `packer`    | Validate Packer templates | [Packer](https://www.packer.io/)                      | Built-in validator              | [Packer validate Command](https://developer.hashicorp.com/packer/docs/commands/validate)      |
| `make tf-fmt`     | `terraform` | Format Terraform files    | [Terraform](https://www.terraform.io/)                | Built-in formatter              | [Terraform fmt Command](https://developer.hashicorp.com/terraform/cli/commands/fmt)           |
| `make tf-lint`    | `terraform` | Lint Terraform code       | [TFLint](https://github.com/terraform-linters/tflint) | [`.tflint.hcl`](../.tflint.hcl) | [TFLint Documentation](https://github.com/terraform-linters/tflint/blob/master/README.md)     |
| `make tf-val`     | `terraform` | Validate Terraform syntax | [Terraform](https://www.terraform.io/)                | Built-in validator              | [Terraform validate Command](https://developer.hashicorp.com/terraform/cli/commands/validate) |

### Testing

| Command       | Purpose                                      | Tool                                      | Reference                                                                   |
|---------------|----------------------------------------------|-------------------------------------------|-----------------------------------------------------------------------------|
| `make bats`   | Run the proxy startup script tests in Docker | [BATS](https://bats-core.readthedocs.io/) | [BATS Documentation](https://bats-core.readthedocs.io/en/stable/usage.html) |
| `make gotest` | Run the Go unit tests of every Go project    | Go testing framework                      | [Go Testing](https://golang.org/pkg/testing/)                               |

`make bats` delegates to [`image/resources/startup/run-tests.sh`](../image/resources/startup/run-tests.sh),
which builds a Docker image from `image/resources/startup/tests/Dockerfile` and runs the `*.bats`
suites inside it, so a working Docker daemon is required.

`make gotest` is an aggregate of the per-project targets below, which can also be run individually:

| Command                           | Project                               |
|-----------------------------------|---------------------------------------|
| `make filter-exports-gotest`      | `image/resources/filter-exports`      |
| `make knfsd-agent-gotest`         | `image/resources/knfsd-agent`         |
| `make knfsd-fsidd-gotest`         | `image/resources/knfsd-fsidd`         |
| `make knfsd-metrics-agent-gotest` | `image/resources/knfsd-metrics-agent` |
| `make netapp-exports-gotest`      | `image/resources/netapp-exports`      |

> NOTE: `image/smoke-tests` is deliberately excluded from `make gotest`, because its tests deploy
> real AWS infrastructure. Run those from the project directory, see
> [Image Smoke Tests](#image-smoke-tests).

### Security Scanning

| Command             | Aliases           | Purpose                          | Tool                                           | Configuration                                                                    | Reference                                                                      |
|---------------------|-------------------|----------------------------------|------------------------------------------------|----------------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| `make scan-checkov` | `checkov`, `scan` | Infrastructure security scan     | [Checkov](https://www.checkov.io/)             | [`.checkov.yaml`](../.checkov.yaml)                                              | [Checkov Documentation](https://www.checkov.io/1.Welcome/Quick%20Start.html)   |
| `make scan-gosec`   | `gosec`           | Go source code security scan     | [Gosec](https://github.com/securego/gosec)     | Built-in rules                                                                   | [Gosec Documentation](https://github.com/securego/gosec/blob/master/README.md) |
| `make scan-kics`    | `kics`, `scan`    | Infrastructure security analysis | [KICS](https://github.com/Checkmarx/kics)      | [`.kics.yaml`](../.kics.yaml)                                                    | [KICS Documentation](https://docs.kics.io/)                                    |
| `make scan-semgrep` | `semgrep`, `scan` | Static code analysis             | [Semgrep](https://semgrep.dev/)                | [`.semgrepignore`](../.semgrepignore)                                            | [Semgrep Documentation](https://semgrep.dev/docs/)                             |
| `make scan-trivy`   | `trivy`, `scan`   | Comprehensive vulnerability scan | [Trivy](https://github.com/aquasecurity/trivy) | [`.trivyignore.yaml`](../.trivyignore.yaml), [`.trivy.tfvars`](../.trivy.tfvars) | [Trivy Documentation](https://trivy.dev/)                                      |

`make scan` runs the Checkov, KICS, Semgrep and Trivy scanners. Use `make security` (alias `sec`) to
additionally include `scan-gosec`. `make scan-kics` runs through
[`run-kics.sh`](../.devcontainer/dev/run-kics.sh) and the Trivy targets write their cache to
`$TRIVY_CACHE_DIR` (`$HOME/.cache/trivy`), which the `dev` container backs with the
`knfsd-dev-trivy-cache` Docker volume so the vulnerability database and checks bundle survive
`make clean` and container rebuilds.

### License Scanning

| Command                | Purpose                        | Tool                                           | Files Created                                     | Reference                                                                      |
|------------------------|--------------------------------|------------------------------------------------|---------------------------------------------------|--------------------------------------------------------------------------------|
| `make lic-scan`        | Scan dependencies for licenses | [Trivy](https://github.com/aquasecurity/trivy) | [`THIRD-PARTY-LICENSES`](../THIRD-PARTY-LICENSES) | [Trivy License Scanning](https://trivy.dev/docs/latest/guide/scanner/license/) |
| `make lic-scan-ignore` | License scan with ignore rules | [Trivy](https://github.com/aquasecurity/trivy) | [`THIRD-PARTY-LICENSES`](../THIRD-PARTY-LICENSES) | [Trivy License Scanning](https://trivy.dev/docs/latest/guide/scanner/license/) |

### Go-specific Commands

The following commands operate across all Go projects in the repository:

| Command       | Aliases      | Purpose                      | Reference                                                 |
|---------------|--------------|------------------------------|-----------------------------------------------------------|
| `make golint` | -            | Lint all Go projects         | [golangci-lint Documentation](https://golangci-lint.run/) |
| `make gosec`  | `scan-gosec` | Go source code security scan | [Gosec](https://github.com/securego/gosec)                |
| `make gotidy` | -            | Tidy Go modules              | [Go Modules](https://golang.org/ref/mod)                  |
| `make goget`  | `goupdate`   | Update Go dependencies       | [Go Modules](https://golang.org/ref/mod)                  |
| `make gotest` | -            | Run the Go unit tests        | [Go Testing](https://golang.org/pkg/testing/)             |

`golint`, `gosec`, `gotidy` and `goget` cover all six Go projects, including `image/smoke-tests`.
`gotest` covers the first five projects only.

## Go Project Makefiles

Each Go project has its own Makefile with standardized targets:

### Project Locations

- [`image/resources/filter-exports/Makefile`](../image/resources/filter-exports/Makefile)
- [`image/resources/knfsd-agent/Makefile`](../image/resources/knfsd-agent/Makefile)
- [`image/resources/knfsd-fsidd/Makefile`](../image/resources/knfsd-fsidd/Makefile)
- [`image/resources/knfsd-metrics-agent/Makefile`](../image/resources/knfsd-metrics-agent/Makefile)
- [`image/resources/netapp-exports/Makefile`](../image/resources/netapp-exports/Makefile)
- [`image/smoke-tests/Makefile`](../image/smoke-tests/Makefile) (see [Image Smoke Tests](#image-smoke-tests))

### Standard Go Targets

| Target               | Purpose                          | Tools Used                                                                             |
|----------------------|----------------------------------|----------------------------------------------------------------------------------------|
| `golint`             | Lint Go code                     | [golangci-lint](https://golangci-lint.run/) with [`.golangci.yaml`](../.golangci.yaml) |
| `gotidy`             | Clean up Go module dependencies  | `go mod tidy`                                                                          |
| `gosec`              | Scan Go code for security issues | `gosec ./...`                                                                          |
| `goget` / `goupdate` | Update Go dependencies           | `go get -t -u ./...` followed by `go mod tidy`                                         |
| `gotest`             | Run Go tests with code coverage  | `go test -cover -vet=all -v ./...`                                                     |

Each project Makefile accepts a `ROOT_DIR` variable so that `golangci-lint` can locate the shared
[`.golangci.yaml`](../.golangci.yaml). It defaults to the repository root relative to the project, so
the targets can also be run directly from the project directory.

### Special Targets

#### KNFSD FSIDD Project

The `knfsd-fsidd` project runs its tests through a helper script instead of calling `go test`
directly:

| Target   | Purpose                                                  |
|----------|----------------------------------------------------------|
| `gotest` | Runs [`test.sh`](../image/resources/knfsd-fsidd/test.sh) |

When developing locally it is faster to run `./test.sh up` once, then `./test.sh run` repeatedly.

#### NetApp Exports Project

The `netapp-exports` project includes an additional target, which every other target in that project
depends on:

| Target     | Purpose                    | Files Created                   |
|------------|----------------------------|---------------------------------|
| `gen_cert` | Generate test certificates | `internal/testcert/testcert.go` |

#### Image Smoke Tests

The `smoke-tests` project has no `gotest` target. Its tests deploy real AWS infrastructure, so they
are run explicitly through the following targets:

| Target         | Purpose                                                        |
|----------------|----------------------------------------------------------------|
| `build-remote` | Cross-compile the `remote.test` binary for the NFS test client |
| `test`         | Run all test stages (apply, check, destroy)                    |
| `apply`        | Apply Terraform infrastructure only                            |
| `check`        | Run tests without applying or destroying Terraform             |
| `destroy`      | Destroy Terraform infrastructure only                          |
| `clean`        | Clean up test artifacts and Terraform files                    |

`build-remote` cross-compiles for the Terraform `ARCH` variable, not the host architecture. Override
it with `TARGET_ARCH` when `ARCH` is not the `amd64` default:

```bash
make test TARGET_ARCH=arm64
```

`make clean` refuses to run while Terraform still holds state, so run `make destroy` first.

## Pre-commit Configuration

The pre-commit system is configured through [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) and includes:

### Local Hooks

These hooks use the project's Makefile targets:

- **ec** - Validates file formatting consistency (`make ec`)
- **codespell** - Checks spelling in code and documentation (`make codespell`)
- **shfmt** - Reports shell script formatting differences (`make shfmt`)
- **shellcheck-sh** - Lints tracked `*.sh` scripts (`make shellcheck-sh`)
- **shellcheck-bash** - Lints tracked `*.bash` scripts (`make shellcheck-bash`)
- **shellcheck-bats** - Lints tracked `*.bats` test files (`make shellcheck-bats`)
- **black** - Formats Python code (`make black`)
- **mypy** - Performs static type checking on Python code (`make mypy`)
- **pylint** - Lints Python code for style and quality issues (`make pylint`)
- **iam-size** - Checks IAM policy JSON files against the AWS size limit (`make iam-size`)
- **packer-format** - Formats Packer HCL files (`make packer-fmt`)
- **packer-validate** - Validates Packer template syntax (`make packer-val`)
- **terraform-format** - Formats Terraform files (`make tf-fmt`)
- **terraform-lint** - Lints Terraform code with TFLint (`make tf-lint`)

> NOTE: `fail_fast` is enabled, so pre-commit stops at the first failing hook. Files matching
> `*.patch` or `*mountstats` are excluded from all hooks.

### External Repository Hooks

#### Pre-commit Hooks (`pre-commit/pre-commit-hooks`)

- **check-added-large-files** - Prevents committing large files
- **check-case-conflict** - Checks for case-insensitive filename conflicts
- **check-json** - Validates JSON syntax
- **check-merge-conflict** - Detects merge conflict markers
- **check-shebang-scripts-are-executable** - Ensures scripts with shebangs are executable
- **check-vcs-permalinks** - Validates VCS permalink formats
- **check-yaml** - Validates YAML syntax (excludes `mkdocs.yml`)
- **check-yaml-unsafe** - Validates `mkdocs.yml` syntax only, allowing the MkDocs `!ENV` custom tag
- **detect-aws-credentials** - Prevents committing AWS credentials
- **detect-private-key** - Prevents committing private keys
- **mixed-line-ending** - Enforces consistent line endings (LF)
- **pretty-format-json** - Formats JSON files consistently (excludes `dashboard.json` files)
- **trailing-whitespace** - Removes trailing whitespace

#### YAMLlint (`adrienverge/yamllint`)

- **yamllint** - Advanced YAML linting with [`.yamllint.yaml`](../.yamllint.yaml) configuration

#### GitLeaks (`zricethezav/gitleaks`)

- **gitleaks** - Scans for secrets and credentials in git history

#### Conventional Commits (`compilerla/conventional-pre-commit`)

- **conventional-pre-commit** - Enforces conventional commit message format

## Configuration Files

| File                                        | Purpose                                    | Tool                                                        |
|---------------------------------------------|--------------------------------------------|-------------------------------------------------------------|
| [`.editorconfig`](../.editorconfig)         | Code formatting consistency across editors | [EditorConfig](https://editorconfig.org/)                   |
| [`.codespellrc`](../.codespellrc)           | Spell checking configuration               | [Codespell](https://github.com/codespell-project/codespell) |
| [`.shellcheckrc`](../.shellcheckrc)         | Shell script linting rules                 | [ShellCheck](https://www.shellcheck.net/)                   |
| [`.yamllint.yaml`](../.yamllint.yaml)       | YAML linting rules                         | [YAMLlint](https://yamllint.readthedocs.io/)                |
| [`.tflint.hcl`](../.tflint.hcl)             | Terraform linting configuration            | [TFLint](https://github.com/terraform-linters/tflint)       |
| [`.golangci.yaml`](../.golangci.yaml)       | Go linting configuration                   | [golangci-lint](https://golangci-lint.run/)                 |
| [`.checkov.yaml`](../.checkov.yaml)         | Infrastructure security scanning           | [Checkov](https://www.checkov.io/)                          |
| [`.kics.yaml`](../.kics.yaml)               | Infrastructure security analysis           | [KICS](https://docs.kics.io/)                               |
| [`.semgrepignore`](../.semgrepignore)       | Static analysis exclusions                 | [Semgrep](https://semgrep.dev/)                             |
| [`.trivyignore.yaml`](../.trivyignore.yaml) | Vulnerability scanning exclusions          | [Trivy](https://trivy.dev/)                                 |
| [`.trivy.tfvars`](../.trivy.tfvars)         | Terraform variables for misconfig scanning | [Trivy](https://trivy.dev/)                                 |
| [`.gitleaksignore`](../.gitleaksignore)     | Secret scanning exclusions                 | [GitLeaks](https://github.com/gitleaks/gitleaks)            |

## VS Code Integration

When working in VS Code, you can easily run pre-commit checks using the integrated terminal:

```bash
# Open terminal in VS Code (Ctrl+` or Cmd+`)
make pc

# Or run specific checks
make lint
make tf-fmt
make golint
```

The terminal will show color-coded output from each tool, making it easy to identify and fix issues.

## Benefits

- **Consistency** - Enforces uniform code style and formatting across the entire codebase
- **Quality** - Catches common programming errors and security vulnerabilities early
- **Automation** - Reduces manual code review overhead by automating style and basic quality checks
- **Standards** - Ensures compliance with industry best practices and coding standards
- **Security** - Prevents accidental commits of secrets, credentials, and vulnerable code patterns
- **Documentation** - Maintains high-quality documentation through spell checking and formatting

## Troubleshooting

### Tool-specific Issues

If individual tools fail:

```bash
# Update tool versions
make pc-update

# Clear pre-commit cache
pre-commit clean

# Run specific hook
pre-commit run <hook-name> --all-files
```

### Go Tool Issues

If Go tools fail:

```bash
# Install/update Go tools
make goget

# Clean Go module cache
go clean -modcache
```
