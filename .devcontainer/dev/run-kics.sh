#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Usage: ./run-kics.sh <path>[optional]

# https://github.com/Checkmarx/kics/releases
KNFSD_KICS_VERSION=2.1.15

KICS_IMAGE=checkmarx/kics:v${KNFSD_KICS_VERSION}

# use the first argument if provided, otherwise use the default path calculation
path="${1:-$(dirname "$(dirname "$(pwd)")")}"

# if running in devcontainer, prefix the host repo path
if [[ $CI == "devcontainer" ]]; then
	root=$(dirname "${HOST_REPO_PATH}")
	path=${root}${path}
fi

# https://docs.kics.io/latest/commands/
docker run --platform linux/amd64 --name kics --interactive --tty --rm \
	--mount type=bind,source="${path}",target=/knfsd-file-cache,readonly "${KICS_IMAGE}" \
	scan -p /knfsd-file-cache --config /knfsd-file-cache/.kics.yaml
