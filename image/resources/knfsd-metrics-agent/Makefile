# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

ROOT_DIR ?= "../../.."

.PHONY: default golint gotidy goget test

.PHONY: default
default:

.PHONY: golint
golint:
	@echo "[golangci-lint]"
	@~/go/bin/golangci-lint run --config=$(ROOT_DIR)/.golangci.yaml --color always --verbose

.PHONY: gotidy
gotidy:
	go mod tidy

.PHONY: goget goupdate
goget goupdate:
	go get -t -u ./...
	go mod tidy

.PHONY: test
test:
	go vet ./...
	go test -race -cover -vet=all -v ./...
