# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

ROOT_DIR ?= "../../.."

.PHONY: default golint goscan gotidy goget test

.PHONY: default
default:

.PHONY: gen_cert
gen_cert:
	@if [ ! -f internal/testcert/testcert.go ]; then \
		go run internal/testcert/gen_certs.go > internal/testcert/testcert.go; \
	fi

.PHONY: golint
golint: gen_cert
	@echo "[golangci-lint]"
	@~/go/bin/golangci-lint run --config=$(ROOT_DIR)/.golangci.yaml --color always --verbose

.PHONY: goscan
goscan: gen_cert
	@echo "[govulncheck]"
	@~/go/bin/govulncheck -test ./...
	@echo "[gosec]"
	@gosec ./...

.PHONY: gotidy
gotidy: gen_cert
	go mod tidy

.PHONY: goget goupdate
goget goupdate: gen_cert
	go get -t -u ./...
	go mod tidy

.PHONY: test
test: gen_cert
	go vet ./...
	go test -race -cover -vet=all -v ./...
