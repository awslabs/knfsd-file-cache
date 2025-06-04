#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# WARNING: this script can download multiple GBs of go modules
# attempt 'go mod tidy/download' command max 3 iterations or
# until success. Execute this script from the .devcontainer dir.
function retry_command() {
	local retval=1
	local attempt=1
	until [[ $retval -eq 0 ]] || [[ $attempt -gt 3 ]]; do
		(
			echo "retry_command: $1"
			set +e
			$1
		)
		retval=$?
		attempt=$((attempt + 1))
		if [[ $retval -ne 0 ]]; then
			sleep 2
		fi
	done
	if [[ $retval -ne 0 ]] && [[ $attempt -gt 3 ]]; then
		exit $retval
	fi
}

cd ../..

for dir in $(find ~+ -name go.mod -exec dirname {} \;); do
	cd "$dir" || exit 1
	echo "caching...$(pwd)"
	retry_command "go mod tidy"
	retry_command "go mod download"
done
