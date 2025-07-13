#!/usr/bin/env bash

# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

shopt -s extglob globstar

function usage() {
	printf 'Syntax: ./update-version.sh <OLD_VERSION> <NEW_VERSION>\n'
	printf '    Example: ./update-version.sh 1.1.0-alpha.4 1.1.0-beta.100\n'
	printf '    Note: Do not include "v" prefix in version parameters\n'
}

# ensure both parameters are provided
if [[ $1 == '' || $2 == '' ]]; then
	usage 1>&2
	exit 2
fi

OLD_VERSION=$1
NEW_VERSION=$2

# search from the root of the repo: /knfsd-file-cache
cd "$(dirname "$0")/../.." || exit 1

# update Terraform and Markdown file references
# exclude ./docs/changes/ as it contains historical information about old releases
find . -type f -and \
	\( -name '*.tf' -or -name '*.md' \) \
	-and \! -path './docs/changes/*' \
	-print0 \
	| while read -rd $'\0' f; do
		sed -i -r "s#(source\s*=\s*\"github.com/awslabs/knfsd-file-cache/.+\?ref=)v$OLD_VERSION\"#\1v$NEW_VERSION\"#g" "$f"
	done

# update VERSION strings in code
find . -type f -not -path "*/\.git/*" -print0 \
	| xargs -0 grep -l "VERSION=\"$OLD_VERSION\"" \
	| while read -r f; do
		sed -i -r "s#VERSION=\"$OLD_VERSION\"#VERSION=\"$NEW_VERSION\"#g" "$f"
	done

echo "Updated version from $OLD_VERSION to $NEW_VERSION"
