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
	"remote.test"
	".terraform"
	"/terraform/.ssh"
	"/terraform/.test-data"
	".terraform.lock.hcl"
	".terraform.tfstate.lock.info"
	"*.tfstate"
	"*.tfstate.backup"
	"*.tfstate.*.backup"
	"packer.log"
	"/image/resources.tgz"
	"db_setup.zip"
	"static_ip.zip"
	"response.json"
	"checkov-report.xml"
	"nfstrace.log"
	"*.drawio.dtmp"
	"*.drawio.bkp"
	"knfsd-metrics-agent.tar.gz"
	"tutorial/nfs-proxy-startup-user-data.sh"
	"tutorial/nfs-client-startup-user-data.sh"
	"__pycache__"
)

# list of dirs (relative to repo root) to delete in delete mode
DIR_TARGETS=(
	".mypy_cache"
	".trivycache"
	"site"
)

cd ../..

if $DELETE_MODE; then
	for dir in "${DIR_TARGETS[@]}"; do
		if [ -d "$dir" ]; then
			echo "Deleted: $dir"
			rm -rf "$dir"
		fi
	done
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
