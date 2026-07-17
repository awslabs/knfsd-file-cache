# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

ROOT_DIR ?= "../.."

GO_FLAGS := $(GO_FLAGS) -v -count=1 -timeout=1h
SINGLE_STAGE := SKIP_apply=true SKIP_check=true SKIP_destroy=true

# Architecture of the remote NFS client the "remote.test" binary is copied to
# and executed on. This is the Terraform "ARCH" variable (default "amd64"), NOT
# the host/dev-container architecture, so "build-remote" cross-compiles the
# binary to match the client. Override to match a non-default "ARCH", e.g.:
#   make test TARGET_ARCH=arm64  (with ARCH="arm64" in terraform.tfvars)
TARGET_ARCH ?= amd64

.PHONY: default
default:

.PHONY: golint
golint:
	@echo "[golangci-lint]"
	@golangci-lint run --config=$(ROOT_DIR)/.golangci.yaml --color always --verbose

.PHONY: gotidy
gotidy:
	go mod tidy

.PHONY: gosec
gosec:
	@go vet ./...
	gosec ./...

.PHONY: goget goupdate
goget goupdate:
	go get -t -u ./...
	go mod tidy

.PHONY: build-remote
build-remote:
	@GOOS=linux GOARCH=$(TARGET_ARCH) go test -c ./cmd/remote

# Runs all the test stages (apply, check, destroy).
# This ensures (best effort) that infrastructure is destroyed even if the tests
# fail. Running the stages individually runs the risk that on an error the
# infrastructure is not destroyed.
.PHONY: test
test: build-remote
	@go test $(GO_FLAGS)

.PHONY: apply
apply: build-remote
	@$(SINGLE_STAGE) SKIP_apply= go test $(GO_FLAGS)

# Runs only the check stage without applying or destroying Terraform. Useful when
# developing tests locally.
.PHONY: check
check: build-remote
	@$(SINGLE_STAGE) SKIP_check= go test $(GO_FLAGS)

.PHONY: destroy
destroy:
	@$(SINGLE_STAGE) SKIP_destroy= go test $(GO_FLAGS)

.PHONY: clean
clean:
	@cd terraform && if [ -f terraform.tfstate ] && [ "$$(terraform state list | wc -l)" -ne 0 ]; then \
		echo >&2 "Terraform has state, run 'make destroy' first."; \
		exit 1; \
	fi
	@rm -rf \
		./remote.test \
		./terraform/terraform.tfstate \
		./terraform/terraform.tfstate.backup \
		./terraform/.terraform \
		./terraform/.terraform.lock.hcl \
		./terraform/.test-data
