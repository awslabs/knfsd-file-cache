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
pre-commit autoupdate

# Update individual Go tools
make goget

# Clean and update pre-commit cache
pre-commit clean
pre-commit install
```

## Make Targets Reference

### Main Makefile Commands

The root [`Makefile`](../Makefile) provides the following targets:

| Command           | Aliases          | Purpose                       | Tools Used                                                        | Files Created                     |
|-------------------|------------------|-------------------------------|-------------------------------------------------------------------|-----------------------------------|
| `make all`        | -                | Run complete validation suite | All linting, Packer, Terraform, BATS, security scanners, Go tools | Various cache and build artifacts |
| `make pre-commit` | `precommit`,`pc` | Run all pre-commit hooks      | [pre-commit](https://pre-commit.com/)                             | -                                 |
| `make lint`       | -                | Run all linting tools         | EditorConfig, Codespell, shfmt, ShellCheck, Black, MyPy, Pylint   | -                                 |

### Code Quality and Formatting

| Command          | Purpose                          | Tool                                                                                 | Configuration                       | Reference                                                                            |
|------------------|----------------------------------|--------------------------------------------------------------------------------------|-------------------------------------|--------------------------------------------------------------------------------------|
| `make ec`        | Validate EditorConfig formatting | [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker) | [`.editorconfig`](../.editorconfig) | [EditorConfig Documentation](https://editorconfig.org/)                              |
| `make codespell` | Check spelling in code and docs  | [Codespell](https://github.com/codespell-project/codespell)                          | [`.codespellrc`](../.codespellrc)   | [Codespell Documentation](https://github.com/codespell-project/codespell)            |
| `make shfmt`     | Format shell scripts             | [shfmt](https://github.com/mvdan/sh)                                                 | [`.editorconfig`](../.editorconfig) | [shfmt Documentation](https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd) |
| `make shellcheck`| Lint shell scripts               | [ShellCheck](https://github.com/koalaman/shellcheck)                                 | Built-in rules                      | [ShellCheck Documentation](https://www.shellcheck.net/)                              |
| `make black`     | Format Python code               | [Black](https://github.com/psf/black)                                                | Python 3.14 target                  | [Black Documentation](https://black.readthedocs.io/)                                 |
| `make mypy`      | Type check Python code           | [MyPy](https://github.com/python/mypy)                                               | Built-in configuration              | [MyPy Documentation](https://mypy.readthedocs.io/)                                   |
| `make pylint`    | Lint Python code                 | [Pylint](https://github.com/pylint-dev/pylint)                                       | Built-in configuration              | [Pylint Documentation](https://pylint.pycqa.org/)                                    |

### Infrastructure as Code

| Command           | Aliases     | Purpose                    | Tool                                                  | Configuration                   | Reference                                                                                     |
|-------------------|-------------|----------------------------|-------------------------------------------------------|---------------------------------|-----------------------------------------------------------------------------------------------|
| `make packer-fmt` | `packer`    | Format Packer HCL files    | [Packer](https://www.packer.io/)                      | Built-in formatter              | [Packer fmt Command](https://developer.hashicorp.com/packer/docs/commands/fmt)                |
| `make packer-val` | `packer`    | Validate Packer templates  | [Packer](https://www.packer.io/)                      | Built-in validator              | [Packer validate Command](https://developer.hashicorp.com/packer/docs/commands/validate)      |
| `make tf-fmt`     | `terraform` | Format Terraform files     | [Terraform](https://www.terraform.io/)                | Built-in formatter              | [Terraform fmt Command](https://developer.hashicorp.com/terraform/cli/commands/fmt)           |
| `make tf-lint`    | `terraform` | Lint Terraform code        | [TFLint](https://github.com/terraform-linters/tflint) | [`.tflint.hcl`](../.tflint.hcl) | [TFLint Documentation](https://github.com/terraform-linters/tflint/blob/master/README.md)     |
| `make tf-val`     | `terraform` | Validate Terraform syntax  | [Terraform](https://www.terraform.io/)                | Built-in validator              | [Terraform validate Command](https://developer.hashicorp.com/terraform/cli/commands/validate) |

### Testing

| Command       | Purpose                       | Tool                                      | Reference                                                                   |
|---------------|-------------------------------|-------------------------------------------|-----------------------------------------------------------------------------|
| `make bats`   | Run BATS deployment tests     | [BATS](https://bats-core.readthedocs.io/) | [BATS Documentation](https://bats-core.readthedocs.io/en/stable/usage.html) |
| `make gotest` | Run all Go project unit tests | Go testing framework                      | [Go Testing](https://golang.org/pkg/testing/)                               |

### Security Scanning

| Command             | Aliases | Purpose                          | Tool                                           | Configuration                               | Reference                                                                     |
|---------------------|---------|----------------------------------|------------------------------------------------|---------------------------------------------|-------------------------------------------------------------------------------|
| `make scan-checkov` | `scan`  | Infrastructure security scan     | [Checkov](https://www.checkov.io/)             | [`.checkov.yaml`](../.checkov.yaml)         | [Checkov Documentation](https://www.checkov.io/1.Welcome/Quick%20Start.html)  |
| `make scan-gosec`   | `scan`  | Go source code security scan     | [Gosec](https://github.com/securego/gosec)     | Built-in rules                              | [Gosec Documentation](https://github.com/securego/gosec/blob/master/README.md)|
| `make scan-kics`    | `scan`  | Infrastructure security analysis | [KICS](https://github.com/Checkmarx/kics)      | [`.kics.yaml`](../.kics.yaml)               | [KICS Documentation](https://docs.kics.io/)                                   |
| `make scan-semgrep` | `scan`  | Static code analysis             | [Semgrep](https://semgrep.dev/)                | Built-in rules                              | [Semgrep Documentation](https://semgrep.dev/docs/)                            |
| `make scan-trivy`   | `scan`  | Comprehensive vulnerability scan | [Trivy](https://github.com/aquasecurity/trivy) | [`.trivyignore.yaml`](../.trivyignore.yaml) | [Trivy Documentation](https://trivy.dev/)                                     |

### License Scanning

| Command               | Purpose                        | Tool                                           | Files Created                                     | Reference                                                                      |
|-----------------------|--------------------------------|------------------------------------------------|---------------------------------------------------|--------------------------------------------------------------------------------|
| `make lic-scan`       | Scan dependencies for licenses | [Trivy](https://github.com/aquasecurity/trivy) | [`THIRD-PARTY-LICENSES`](../THIRD-PARTY-LICENSES) | [Trivy License Scanning](https://trivy.dev/docs/latest/guide/scanner/license/) |
| `make lic-scan-ignore`| License scan with ignore rules | [Trivy](https://github.com/aquasecurity/trivy) | [`THIRD-PARTY-LICENSES`](../THIRD-PARTY-LICENSES) | [Trivy License Scanning](https://trivy.dev/docs/latest/guide/scanner/license/) |

### Go-specific Commands

The following commands operate across all Go projects in the repository:

| Command       | Aliases      | Purpose                       | Reference                                                 |
|---------------|--------------|-------------------------------|-----------------------------------------------------------|
| `make golint` | -            | Lint all Go projects          | [golangci-lint Documentation](https://golangci-lint.run/) |
| `make gosec`  | `scan-gosec` | Go source code security scan  | [Gosec](https://github.com/securego/gosec)                |
| `make gotidy` | -            | Tidy Go modules               | [Go Modules](https://golang.org/ref/mod)                  |
| `make goget`  | `goupdate`   | Update Go dependencies        | [Go Modules](https://golang.org/ref/mod)                  |

## Go Project Makefiles

Each Go project has its own Makefile with standardized targets:

### Project Locations

- [`image/resources/filter-exports/Makefile`](../image/resources/filter-exports/Makefile)
- [`image/resources/knfsd-agent/Makefile`](../image/resources/knfsd-agent/Makefile)
- [`image/resources/knfsd-fsidd/Makefile`](../image/resources/knfsd-fsidd/Makefile)
- [`image/resources/knfsd-metrics-agent/Makefile`](../image/resources/knfsd-metrics-agent/Makefile)
- [`image/resources/netapp-exports/Makefile`](../image/resources/netapp-exports/Makefile)
- [`image/smoke-tests/Makefile`](../image/smoke-tests/Makefile)

### Standard Go Targets

| Target               | Purpose                          | Tools Used                                                                             |
|----------------------|----------------------------------|----------------------------------------------------------------------------------------|
| `golint`             | Lint Go code                     | [golangci-lint](https://golangci-lint.run/) with [`.golangci.yaml`](../.golangci.yaml) |
| `gotidy`             | Clean up Go module dependencies  | `go mod tidy`                                                                          |
| `goget` / `goupdate` | Update Go dependencies           | `go get -t -u ./...`                                                                   |
| `test`               | Run Go tests with code coverage  | `go test -cover -vet=all -v ./...`                                                     |

### Special Targets

#### NetApp Exports Project

The `netapp-exports` project includes an additional target:

| Target     | Purpose                    | Files Created                   |
|------------|----------------------------|---------------------------------|
| `gen_cert` | Generate test certificates | `internal/testcert/testcert.go` |

#### Image Smoke Tests

The `smoke-tests` project includes additional testing targets:

| Target         | Purpose                                  |
|----------------|------------------------------------------|
| `build-remote` | Build remote test binary                 |
| `apply`        | Apply Terraform infrastructure           |
| `check`        | Run tests without infrastructure changes |
| `destroy`      | Destroy Terraform infrastructure         |
| `clean`        | Clean up test artifacts                  |

## Pre-commit Configuration

The pre-commit system is configured through [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) and includes:

### Local Hooks

These hooks use the project's Makefile targets:

- **editorconfig** - Validates file formatting consistency
- **codespell** - Checks spelling in code and documentation
- **shfmt** - Formats shell scripts
- **shellcheck** - Lints shell scripts for common issues
- **black** - Formats Python code to Python 3.14 standards
- **mypy** - Performs static type checking on Python code
- **pylint** - Lints Python code for style and quality issues
- **packer-format** - Formats Packer HCL files
- **packer-validate** - Validates Packer template syntax
- **terraform-format** - Formats Terraform files
- **terraform-lint** - Lints Terraform code with TFLint

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
- **pretty-format-json** - Formats JSON files consistently
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
| [`.yamllint.yaml`](../.yamllint.yaml)       | YAML linting rules                         | [YAMLlint](https://yamllint.readthedocs.io/)                |
| [`.tflint.hcl`](../.tflint.hcl)             | Terraform linting configuration            | [TFLint](https://github.com/terraform-linters/tflint)       |
| [`.golangci.yaml`](../.golangci.yaml)       | Go linting configuration                   | [golangci-lint](https://golangci-lint.run/)                 |
| [`.checkov.yaml`](../.checkov.yaml)         | Infrastructure security scanning           | [Checkov](https://www.checkov.io/)                          |
| [`.trivyignore.yaml`](../.trivyignore.yaml) | Vulnerability scanning exclusions          | [Trivy](https://trivy.dev/)                                 |

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
pre-commit autoupdate

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
