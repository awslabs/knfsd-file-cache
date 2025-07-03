#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Usage: ./run-kics.sh <path>[optional]

# https://github.com/Checkmarx/kics/releases
KNFSD_KICS_VERSION=2.1.10

KICS_IMAGE=checkmarx/kics:v${KNFSD_KICS_VERSION}

# Use the first argument if provided, otherwise use the default path calculation
path="${1:-$(dirname "$(dirname "$(pwd)")")}"

if [[ $CI == "devcontainer" ]]; then
	root=$(dirname "${HOST_REPO_PATH}")
	path=${root}${path}
fi

# https://docs.kics.io/latest/commands/
docker run --platform linux/amd64 --name kics --interactive --tty --rm \
	--mount type=bind,source="${path}",target=/knfsd-file-cache,readonly "${KICS_IMAGE}" \
	scan -p /knfsd-file-cache --config /knfsd-file-cache/.kics.yaml
