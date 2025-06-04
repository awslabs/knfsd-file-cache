#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Search recursively through the git repo for specific files and dirs

# Usage: ./find_temp_files.sh [-d/--delete]

# check script is being run from the .devcontainer/dev dir only
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWD="$(pwd)"

if [[ $CWD != "$SCRIPT_DIR" ]]; then
	echo "ERROR: Please run this script from the .devcontainer/dev directory."
	exit 1
fi

# check for delete flag
DELETE_MODE=false
if [[ $1 == "-d" || $1 == "--delete" ]]; then
	DELETE_MODE=true
	echo "WARNING: Running in delete mode. Found files will be deleted."
	echo "Press Ctrl+C within 3 seconds to abort..."
	sleep 3
fi

# list of files and dirs to search for
SEARCH_TARGETS=(
	"Thumbs.db"
	".DS_Store"
	".terraform"
	".terraform.lock.hcl"
	".terraform.tfstate.lock.info"
	"*.tfstate"
	"*.tfstate.backup"
	"*.tfstate.*.backup"
	"packer.log"
	"/image.manifest.json"
	"/image/resources.tgz"
	"db_setup.zip"
	"static_ip.zip"
	"response.json"
	"checkov-report.xml"
	"nfstrace.log"
	"*.drawio.dtmp"
	"*.drawio.bkp"
	"knfsd-metrics-agent.tar.gz"
)

cd ../..

if $DELETE_MODE; then
	rm -rf .mypy_cache
	rm -rf .trivycache
fi

for target in "${SEARCH_TARGETS[@]}"; do
	if [[ $target == *"*"* ]]; then
		# use find for wildcard patterns
		find . -type f -name "$target" -not -path "*/\.git/*" 2> /dev/null | while read -r file; do
			if $DELETE_MODE; then
				echo "Deleted: $file"
				rm -f "$file"
			else
				echo "Found: $file"
			fi
		done
	else
		# use find for specific files/directories
		find . -path "*$target*" -not -path "*/\.git/*" 2> /dev/null | while read -r file; do
			if $DELETE_MODE; then
				echo "Deleted: $file"
				if [ -d "$file" ]; then
					rm -rf "$file"
				else
					rm -f "$file"
				fi
			else
				echo "Found: $file"
			fi
		done
	fi
done
