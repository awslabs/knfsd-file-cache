# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

ROOT_DIR ?= "../../.."

.PHONY: default golint gotidy gosec goget gotest

.PHONY: default
default:

.PHONY: golint
golint:
	@echo "[golangci-lint]"
	@golangci-lint run --config=$(ROOT_DIR)/.golangci.yaml --color always --verbose

.PHONY: gotidy
gotidy:
	go mod tidy

.PHONY: goget goupdate
goget goupdate:
	go get -t -u ./...
	go mod tidy

.PHONY: gosec
gosec:
	gosec ./...

.PHONY: gotest
gotest:
	go test -cover -vet=all -v ./...
