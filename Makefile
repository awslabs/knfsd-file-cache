# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This provides a convenient way to quickly run all the basic tests locally.
# When running in CI/CD (eg. AWS Code Build) these steps should be separated out
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
all: lint packer terraform bats scan golint goscan test

.PHONY: pre-commit precommit pc
pre-commit precommit pc:
	@pre-commit run --all-files

.PHONY: lic-scan
lic-scan:
	@echo "[license scan]"
	@trivy fs --scanners license --license-full $(ROOT_DIR)

.PHONY: lic-scan-ignore
lic-scan-ignore:
	@echo "[license scan, ignore]"
	@trivy fs --scanners license --license-full --ignorefile $(ROOT_DIR)/.trivyignore.yaml $(ROOT_DIR)

.PHONY: lint ec codespell shfmt shellcheck black mypy pylint
lint: ec codespell shfmt shellcheck black mypy pylint

ec:
	@echo "[ec]"
	@editorconfig-checker 2>/dev/null

codespell:
	@echo "[codespell]"
	@codespell --skip "go.mod,go.sum,slabinfo"

shfmt:
	@echo "[shfmt]"
	@shfmt -d -s .

shellcheck:
	@echo "[shellcheck]"
	@git ls-files --exclude='*.sh' --ignored -c -z | xargs -0r shellcheck --shell=bash --external-sources --color=always --severity=style
	@git ls-files --exclude='*.bash' --ignored -c -z | xargs -0r shellcheck --shell=bash --external-sources --color=always --severity=style
	@git ls-files --exclude='*.bats' --ignored -c -z | xargs -0r shellcheck --shell=bash --external-sources --color=always --severity=style

black:
	@echo "[black]"
	@black --target-version py313 --quiet .

mypy:
	@echo "[mypy]"
	@if [ "$$CI" = "devcontainer" ]; then \
		/home/$(USERNAME)/.venv/bin/python -m mypy --follow-untyped-imports --no-error-summary --show-error-context --pretty .; \
	else \
		mypy --follow-untyped-imports --no-error-summary --show-error-context --pretty .; \
	fi

pylint:
	@echo "[pylint]"
	@if [ "$$CI" = "devcontainer" ]; then \
		/home/$(USERNAME)/.venv/bin/python -m pylint --output-format=colorized --score=n .; \
	else \
		pylint --output-format=colorized --score=n .; \
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
	@#echo "[packer validate 'testing/images/client']"
	@#cd $(ROOT_DIR)/testing/images/client && packer validate .

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
	@cd $(ROOT_DIR)/deployment/terraform-module-knfsd/resources && ./run-tests.sh

.PHONY: scan-semgrep
scan: scan-semgrep
scan-semgrep:
	@echo "[semgrep]"
	@semgrep scan --no-git-ignore --no-rewrite-rule-ids $(ROOT_DIR)

.PHONY: scan-checkov
scan: scan-checkov
scan-checkov:
	@echo "[checkov]"
	@checkov --config-file $(ROOT_DIR)/.checkov.yaml

.PHONY: scan-tfsec
scan: scan-tfsec
scan-tfsec:
	@echo "[tfsec]"
	@tfsec --force-all-dirs -f lovely --config-file $(ROOT_DIR)/.tfsec.yaml

.PHONY: scan-trivy
scan: scan-trivy
scan-trivy:
	@echo "[trivy]"
	@trivy fs --ignorefile $(ROOT_DIR)/.trivyignore.yaml --exit-code 1 \
		--cache-dir "$(ROOT_DIR)/.trivycache" \
		--scanners secret,vuln,misconfig,license $(ROOT_DIR)

.PHONY: scan-kics
scan: scan-kics
scan-kics:
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
	@$(MAKE) ROOT_DIR=$(ROOT_DIR) -C testing/examples golint

.PHONY: goscan
goscan:
	$(MAKE) -C image/resources/filter-exports goscan
	$(MAKE) -C image/resources/knfsd-agent goscan
	$(MAKE) -C image/resources/knfsd-fsidd goscan
	$(MAKE) -C image/resources/knfsd-metrics-agent goscan
	$(MAKE) -C image/resources/netapp-exports goscan
	$(MAKE) -C image/smoke-tests goscan
	$(MAKE) -C testing/examples goscan

.PHONY: gotidy
gotidy:
	$(MAKE) -C image/resources/filter-exports gotidy
	$(MAKE) -C image/resources/knfsd-agent gotidy
	$(MAKE) -C image/resources/knfsd-fsidd gotidy
	$(MAKE) -C image/resources/knfsd-metrics-agent gotidy
	$(MAKE) -C image/resources/netapp-exports gotidy
	$(MAKE) -C image/smoke-tests gotidy
	$(MAKE) -C testing/examples gotidy

.PHONY: goget goupdate
goget goupdate:
	$(MAKE) -C image/resources/filter-exports goget
	$(MAKE) -C image/resources/knfsd-agent goget
	$(MAKE) -C image/resources/knfsd-fsidd goget
	$(MAKE) -C image/resources/knfsd-metrics-agent goget
	$(MAKE) -C image/resources/netapp-exports goget
	$(MAKE) -C image/smoke-tests goget
	$(MAKE) -C testing/examples goget

.PHONY: filter-exports-test
test: filter-exports-test
filter-exports-test:
	$(MAKE) -C image/resources/filter-exports test

.PHONY: knfsd-agent-test
test: knfsd-agent-test
knfsd-agent-test:
	$(MAKE) -C image/resources/knfsd-agent test

.PHONY: knfsd-fsidd-test
test: knfsd-fsidd-test
knfsd-fsidd-test:
	$(MAKE) -C image/resources/knfsd-fsidd test

.PHONY: knfsd-metrics-agent-test
test: knfsd-metrics-agent-test
knfsd-metrics-agent-test:
	$(MAKE) -C image/resources/knfsd-metrics-agent test

.PHONY: netapp-exports-test
test: netapp-exports-test
netapp-exports-test:
	$(MAKE) -C image/resources/netapp-exports test
