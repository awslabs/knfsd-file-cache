# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

ROOT_DIR ?= "../../.."

.PHONY: default golint gotidy gosec goget test

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
	@golangci-lint run --config=$(ROOT_DIR)/.golangci.yaml --color always --verbose

.PHONY: gotidy
gotidy: gen_cert
	go mod tidy

.PHONY: gosec
gosec: gen_cert
	gosec ./...

.PHONY: goget goupdate
goget goupdate: gen_cert
	go get -t -u ./...
	go mod tidy

.PHONY: test
test: gen_cert
	go test -cover -vet=all -v ./...
