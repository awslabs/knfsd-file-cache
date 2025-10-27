#!/usr/bin/env bash

# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

shopt -s extglob globstar

function usage() {
	printf 'Syntax: ./update-version.sh <OLD_VERSION> <NEW_VERSION>\n'
	printf '    Example: ./update-version.sh 1.1.0-alpha.999 1.1.0-beta.999\n'
}

# check for help flags
if [[ $1 == '-h' || $1 == '--help' || $1 == 'help' ]]; then
	usage
	exit 0
fi

# ensure both parameters are provided
if [[ $1 == '' || $2 == '' ]]; then
	usage 1>&2
	exit 2
fi

OLD_VERSION=$1
NEW_VERSION=$2

# Strip leading "v" if present (e.g., v1.1.0 -> 1.1.0)
OLD_VERSION=${OLD_VERSION#v}
NEW_VERSION=${NEW_VERSION#v}

# search from the root of the repo: /knfsd-file-cache
cd "$(dirname "$0")/../.." || exit 1

# update Terraform, Packer, and Markdown file references
# exclude CHANGELOG.md as it contains historical information about old releases
find . -type f -and \
	\( -name '*.tf' -or -name '*.pkr.hcl' -or -name '*.md' \) \
	-and \! -name 'CHANGELOG.md' \
	-print0 \
	| while read -rd $'\0' f; do
		# Update module source references with v prefix
		sed -i -r "s#(source\s*=\s*\"github.com/awslabs/knfsd-file-cache/.+\?ref=)v$OLD_VERSION\"#\1v$NEW_VERSION\"#g" "$f"
		# Update any standalone version strings (without v prefix)
		sed -i -r "s#$OLD_VERSION#$NEW_VERSION#g" "$f"
	done

# update VERSION strings in code
find . -type f -not -path "*/\.git/*" -print0 \
	| xargs -0 grep -l "VERSION=\"$OLD_VERSION\"" \
	| while read -r f; do
		sed -i -r "s#VERSION=\"$OLD_VERSION\"#VERSION=\"$NEW_VERSION\"#g" "$f"
	done

echo "Updated version from $OLD_VERSION to $NEW_VERSION"
