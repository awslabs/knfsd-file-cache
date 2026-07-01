# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This provides a convenient way to quickly run all the tests locally.
# When running in CI/CD (eg. AWS Code Build or GitLab) these steps should be separated out
# so they can run in parallel, and to log the output from each step independently.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
USERNAME := $(shell id -un)
TF_DIRS := $(sort $(dir $(shell find $(ROOT_DIR) -name "*.tf")))
SHELL_BLUE := "\033[0;34m"
SHELL_DEFAULT := "\033[0m"

.PHONY: default
default:

.PHONY: all
all: lint packer terraform bats scan golint gotest

.PHONY: security sec
security sec: scan-checkov scan-gosec scan-kics scan-semgrep scan-trivy

.PHONY: image
image:
	@packer init -upgrade image/knfsd.pkr.hcl
	@packer build -var-file image/image.pkrvars.hcl image

.PHONY: image-debug
image-debug:
	@packer init -upgrade image/knfsd.pkr.hcl
	@PACKER_LOG=1 PACKER_LOG_PATH=packer.log packer build -debug -var-file image/image.pkrvars.hcl image

.PHONY: image-log
image-log:
	@packer init -upgrade image/knfsd.pkr.hcl
	@PACKER_LOG=1 PACKER_LOG_PATH=packer.log packer build -var-file image/image.pkrvars.hcl image

.PHONY: iamlive
iamlive:
	@: > iamlive.json
	@echo "iamlive listening on 127.0.0.1:10080. Ctrl+C to exit"
	@iamlive --set-ini --mode proxy --output-file iamlive.json

.PHONY: image-iam
image-iam:
	@(echo > /dev/tcp/127.0.0.1/10080) 2> /dev/null || { \
		echo "ERROR: iamlive is not listening on 127.0.0.1:10080. Run 'make iamlive' first"; \
		exit 1; \
	}
	@test -f "$$HOME/.iamlive/ca.pem" || { \
		echo "ERROR: ~/.iamlive/ca.pem not found. Run 'make iamlive' first to generate it"; \
		exit 1; \
	}
	@sudo bash -c "cp '$$HOME/.iamlive/ca.pem' /usr/local/share/ca-certificates/iamlive.crt && update-ca-certificates > /dev/null 2>&1"
	@packer init -upgrade image/knfsd.pkr.hcl
	@export AWS_CA_BUNDLE="$$HOME/.iamlive/ca.pem"; \
	export HTTP_PROXY=http://127.0.0.1:10080; \
	export HTTPS_PROXY=http://127.0.0.1:10080; \
	packer build -var-file image/image.pkrvars.hcl image

.PHONY: pre-commit precommit pc
pre-commit precommit pc:
	@pre-commit run --all-files

.PHONY: pre-commit-update precommit-update pc-update autoupdate
pre-commit-update precommit-update pc-update autoupdate:
	@pre-commit autoupdate

.PHONY: clean delete del
clean delete del:
	@cd $(ROOT_DIR)/.devcontainer/dev && ./find_temp_files.sh -d

.PHONY: lic-scan
lic-scan:
	@echo "[license scan]"
	@trivy fs --scanners license --license-full $(ROOT_DIR)

.PHONY: lic-scan-ignore
lic-scan-ignore:
	@echo "[license scan, ignore]"
	@trivy fs --scanners license --license-full --ignorefile $(ROOT_DIR)/.trivyignore.yaml $(ROOT_DIR)

.PHONY: lint ec codespell shfmt shellcheck-sh shellcheck-bash shellcheck-bats black mypy pylint iam-size
lint: ec codespell shfmt shellcheck-sh shellcheck-bash shellcheck-bats black mypy pylint iam-size

ec:
	@echo "[ec]"
	@editorconfig-checker 2>/dev/null

codespell:
	@echo "[codespell]"
	@codespell --config $(ROOT_DIR)/.codespellrc

shfmt:
	@echo "[shfmt]"
	@shfmt -d .

shellcheck-sh:
	@echo "[shellcheck-sh]"
	@git ls-files --exclude='*.sh' --ignored -c -z | xargs -0r shellcheck --shell=bash --external-sources --color=always --severity=style

shellcheck-bash:
	@echo "[shellcheck-bash]"
	@git ls-files --exclude='*.bash' --ignored -c -z | xargs -0r shellcheck --shell=bash --external-sources --color=always --severity=style

shellcheck-bats:
	@echo "[shellcheck-bats]"
	@git ls-files --exclude='*.bats' --ignored -c -z | xargs -0r shellcheck --shell=bash --external-sources --color=always --severity=style

black:
	@echo "[black]"
	@black --target-version py312 --quiet .

mypy:
	@echo "[mypy]"
	@if [ "$$CI" = "devcontainer" ]; then \
		/opt/venv/bin/python -m mypy --follow-untyped-imports --no-error-summary --show-error-context --pretty .; \
	else \
		mypy --follow-untyped-imports --no-error-summary --show-error-context --pretty .; \
	fi

pylint:
	@echo "[pylint]"
	@if [ "$$CI" = "devcontainer" ]; then \
		/opt/venv/bin/python -m pylint --output-format=colorized --score=n .; \
	else \
		pylint --output-format=colorized --score=n .; \
	fi

define IAM_SIZE_PY
import glob, json, re, sys
LIMIT = 6144
PATTERNS = ("docs/iam/*.json", "examples/*/iam.json")
RED = "\033[31m" if sys.stderr.isatty() else ""
RESET = "\033[0m" if sys.stderr.isatty() else ""
fails = []
files = sorted({p for pattern in PATTERNS for p in glob.glob(pattern)})
if not files:
	sys.stderr.write(
		f"[iam-size] {RED}ERROR:{RESET} no files matched any of {PATTERNS}\n"
	)
	sys.exit(1)
for path in files:
	with open(path, encoding="utf-8") as fh:
		raw = fh.read()
	try:
		json.loads(raw)
	except json.JSONDecodeError as exc:
		sys.stderr.write(f"{RED}ERROR: {path} is not valid JSON: {exc}{RESET}\n")
		sys.exit(1)
	n = len(re.sub(r"\s", "", raw))
	if n > LIMIT:
		fails.append((path, n))
if fails:
	sys.stderr.write(
		f"{RED}ERROR: IAM policy JSON must fit the AWS customer-managed-policy 6,144 character limit{RESET}\n"
	)
	for path, n in fails:
		sys.stderr.write(f"  {path}: over by {n - LIMIT} chars\n")
	sys.exit(1)
endef
export IAM_SIZE_PY

.PHONY: iam-size
iam-size:
	@echo "[iam-size]"
	@if [ "$$CI" = "devcontainer" ]; then \
		/opt/venv/bin/python -c "$$IAM_SIZE_PY"; \
	else \
		python3 -c "$$IAM_SIZE_PY"; \
	fi

.PHONY: packer-format
packer: packer-fmt
packer-fmt:
	@echo "[packer fmt]"
	@packer init -upgrade $(ROOT_DIR)/image
	@packer fmt -recursive $(ROOT_DIR)

.PHONY: packer-validate
packer: packer-val
packer-val:
	@echo "[packer validate 'image']"
	@cd $(ROOT_DIR)/image && packer validate .

.PHONY: terraform-format
terraform: tf-fmt
tf-fmt:
	@echo "[terraform fmt]"
	@terraform fmt -recursive $(ROOT_DIR)

.PHONY: terraform-lint
terraform: tf-lint
tf-lint:
	@echo "[tflint]"
	@tflint --init
	@tflint --recursive --config="$(ROOT_DIR)/.tflint.hcl" --format compact

.PHONY: terraform-validate
terraform: tf-val
tf-val:
	@echo "[terraform validate]"
	@FAILED=0; \
	for dir in $(TF_DIRS); do (\
		echo -e Validating: ${SHELL_BLUE}$$dir${SHELL_DEFAULT}; \
		cd $$dir || exit 1; \
		terraform init -backend=false -reconfigure -upgrade; \
		if ! terraform validate; then \
			FAILED=1; \
		fi); \
	done; \
	exit $$FAILED

.PHONY: bats
bats:
	@echo "[bats]"
	@cd $(ROOT_DIR)/image/resources/startup && ./run-tests.sh

.PHONY: scan-semgrep
scan: scan-semgrep semgrep
scan-semgrep semgrep:
	@echo "[semgrep]"
	@semgrep scan --no-git-ignore --no-rewrite-rule-ids $(ROOT_DIR)

.PHONY: scan-checkov
scan: scan-checkov checkov
scan-checkov checkov:
	@echo "[checkov]"
	@checkov --config-file $(ROOT_DIR)/.checkov.yaml

.PHONY: scan-trivy
scan: scan-trivy trivy
scan-trivy trivy:
	@echo "[trivy]"
	@trivy fs --ignorefile $(ROOT_DIR)/.trivyignore.yaml --exit-code 1 \
		--cache-dir "$(ROOT_DIR)/.trivycache" \
		--tf-vars $(ROOT_DIR)/.trivy.tfvars \
		--scanners secret,vuln,misconfig,license $(ROOT_DIR)

.PHONY: scan-kics kics
scan: scan-kics
scan-kics kics:
	@echo "[kics]"
	@$(ROOT_DIR)/.devcontainer/dev/run-kics.sh $(ROOT_DIR)

.PHONY: golint
golint:
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/filter-exports golint
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/knfsd-agent golint
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/knfsd-fsidd golint
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/knfsd-metrics-agent golint
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/netapp-exports golint
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/smoke-tests golint

.PHONY: gosec scan-gosec
gosec scan-gosec:
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/filter-exports gosec
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/knfsd-agent gosec
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/knfsd-fsidd gosec
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/knfsd-metrics-agent gosec
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/resources/netapp-exports gosec
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C image/smoke-tests gosec

.PHONY: gotidy
gotidy:
	$(MAKE) -C image/resources/filter-exports gotidy
	$(MAKE) -C image/resources/knfsd-agent gotidy
	$(MAKE) -C image/resources/knfsd-fsidd gotidy
	$(MAKE) -C image/resources/knfsd-metrics-agent gotidy
	$(MAKE) -C image/resources/netapp-exports gotidy
	$(MAKE) -C image/smoke-tests gotidy

.PHONY: goget goupdate
goget goupdate:
	$(MAKE) -C image/resources/filter-exports goget
	$(MAKE) -C image/resources/knfsd-agent goget
	$(MAKE) -C image/resources/knfsd-fsidd goget
	$(MAKE) -C image/resources/knfsd-metrics-agent goget
	$(MAKE) -C image/resources/netapp-exports goget
	$(MAKE) -C image/smoke-tests goget

.PHONY: filter-exports-gotest
gotest: filter-exports-gotest
filter-exports-gotest:
	$(MAKE) -C image/resources/filter-exports gotest

.PHONY: knfsd-agent-gotest
gotest: knfsd-agent-gotest
knfsd-agent-gotest:
	$(MAKE) -C image/resources/knfsd-agent gotest

.PHONY: knfsd-fsidd-gotest
gotest: knfsd-fsidd-gotest
knfsd-fsidd-gotest:
	$(MAKE) -C image/resources/knfsd-fsidd gotest

.PHONY: knfsd-metrics-agent-gotest
gotest: knfsd-metrics-agent-gotest
knfsd-metrics-agent-gotest:
	$(MAKE) -C image/resources/knfsd-metrics-agent gotest

.PHONY: netapp-exports-gotest
gotest: netapp-exports-gotest
netapp-exports-gotest:
	$(MAKE) -C image/resources/netapp-exports gotest

