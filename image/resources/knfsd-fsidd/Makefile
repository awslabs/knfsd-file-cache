# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

ROOT_DIR ?= "../../.."

.PHONY: default golint goscan gotidy goget test test-codebuild

.PHONY: default
default:

.PHONY: golint
golint:
	@echo "[golangci-lint]"
	@~/go/bin/golangci-lint run --config=$(ROOT_DIR)/.golangci.yaml --color always --verbose

.PHONY: goscan
goscan:
	@echo "[govulncheck]"
	@~/go/bin/govulncheck -test ./...
	@echo "[gosec]"
	@gosec ./...

.PHONY: gotidy
gotidy:
	go mod tidy

.PHONY: goget goupdate
goget goupdate:
	go get -t -u ./...
	go mod tidy

# NOTE: AWS Code Build doesn't use this Makefile as it needs to run the individual
# up/run/down steps on different containers. This is just a stub for consistency
# with the other tools.
# When developing locally it's faster when repeatedly running tests to
# use once "./test.sh up", then use "./test.sh run".
test:
	./test.sh
