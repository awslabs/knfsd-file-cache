#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## Pin every GitHub Actions "uses:" reference found in ".github/workflows" to the
## full 40-character commit SHA of the action's latest release, keeping the
## resolved release tag as a trailing comment:
##   uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
## The latest release is the highest "vX.Y.Z" tag, so pre-release and bundle tags
## (for example "codeql-bundle-v2.26.2") are ignored. A tag that looks like a
## release but is flagged upstream as a pre-release, or as an unpublished draft, is
## dropped too, as such a tag is not a release to pin to.
## Local ("./.github/actions/...") and Docker ("docker://...") references are
## skipped as they have no upstream commit SHA to resolve.
## Set GITHUB_COM_TOKEN to raise the GitHub API rate limit (60 to 5000 req/hour).

## USAGE:
## ./update-github-action-shas.sh            report outdated actions only, exit 1 if any
## ./update-github-action-shas.sh --write    rewrite the workflow files in place

set -eo pipefail

SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_YELLOW='\033[0;33m'
SHELL_BLUE='\033[0;34m'
SHELL_DEFAULT='\033[0m'

GITHUB_API="https://api.github.com"
# tags returned per page; 100 is the GitHub API maximum
TAGS_PER_PAGE=100
# an upper bound on the tag pages to walk, so a busy repo cannot loop forever
MAX_TAG_PAGES=5
# releases read per repo, newest first; a single page is enough, as a pre-release
# able to outrank the current release is always among the newest releases
RELEASES_PER_PAGE=100
# a release tag must look like "1.2.3" or "v1.2.3"
SEMVER_TAG='^v?[0-9]+\.[0-9]+\.[0-9]+$'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)/.github/workflows"

function usage() {
	printf 'Syntax: ./update-github-action-shas.sh [-w/--write]\n'
	printf '    Default:    report actions that are not pinned to their latest release\n'
	printf '    -w/--write: rewrite the .github/workflows files in place\n'
}

# check for help flags
if [[ $1 == '-h' || $1 == '--help' || $1 == 'help' ]]; then
	usage
	exit 0
fi

# check for write flag
WRITE_MODE=false
if [[ $1 == '-w' || $1 == '--write' ]]; then
	WRITE_MODE=true
elif [[ -n $1 ]]; then
	usage 1>&2
	exit 2
fi

# check the required tools are installed
for binary in curl jq; do
	if ! command -v "${binary}" > /dev/null 2>&1; then
		echo -e "${SHELL_RED}ERROR: ${binary} not found in \$PATH${SHELL_DEFAULT}"
		exit 1
	fi
done

if [[ ! -d ${WORKFLOW_DIR} ]]; then
	echo -e "${SHELL_RED}ERROR: workflow directory not found at: ${WORKFLOW_DIR}${SHELL_DEFAULT}"
	exit 1
fi

# authenticate when a token is available to avoid the low anonymous rate limit
CURL_ARGS=(--silent --show-error --fail --max-time 30 --header "Accept: application/vnd.github+json")
if [[ -n ${GITHUB_COM_TOKEN} ]]; then
	CURL_ARGS+=(--header "Authorization: Bearer ${GITHUB_COM_TOKEN}")
fi

# cache of "owner/repo" to "tag sha" to avoid repeat API calls for shared actions
declare -A RESOLVED=()

# print the tag names the repo flags as a pre-release or an unpublished draft
# such a tag can still match SEMVER_TAG, as with the "v3.9.0" pre-release tagged
# while "v3.8.0" is the latest release of "editorconfig-checker", so it has to be
# excluded by name rather than by the shape of the version
# an unreadable release list yields nothing, leaving the tag filtering unchanged
function unstable_tags() {
	local repo=$1
	curl "${CURL_ARGS[@]}" \
		"${GITHUB_API}/repos/${repo}/releases?per_page=${RELEASES_PER_PAGE}" 2> /dev/null \
		| jq -r '.[] | select(.prerelease == true or .draft == true)
			| .tag_name // empty' 2> /dev/null \
		|| true
}

# print "<tag> <sha>" for the latest release of the given "owner/repo"
# the tags endpoint is the source, as it is the only one that reports the commit
# SHA to pin to, with the tags flagged upstream as a pre-release removed
function resolve_latest_release() {
	local repo=$1
	local page=1
	local json='' tags='' unstable=''

	unstable=$(unstable_tags "${repo}")

	# walk the tag pages until a short page signals the last one
	while ((page <= MAX_TAG_PAGES)); do
		json=$(curl "${CURL_ARGS[@]}" \
			"${GITHUB_API}/repos/${repo}/tags?per_page=${TAGS_PER_PAGE}&page=${page}") || return 1

		# the tags endpoint reports the commit SHA, so annotated tags need no deref
		tags+=$(jq -r --arg semver "${SEMVER_TAG}" \
			'.[] | select(.name | test($semver)) | "\(.name) \(.commit.sha)"' <<< "${json}")
		tags+=$'\n'

		if (($(jq -r 'length' <<< "${json}") < TAGS_PER_PAGE)); then
			break
		fi
		page=$((page + 1))
	done

	tags=$(sed '/^$/d' <<< "${tags}")

	if [[ -n ${unstable} && -n ${tags} ]]; then
		# compare the tag field alone, so neither the trailing SHA nor a longer
		# tag that merely starts with a flagged one can affect the result
		tags=$(awk 'NR == FNR { drop[$0] = 1; next } !($1 in drop)' \
			<(printf '%s\n' "${unstable}") <(printf '%s\n' "${tags}")) || tags=''
	fi

	# highest semantic version wins; "sort -V" orders v6.0.3 before v7.0.1
	printf '%s' "${tags}" | sed '/^$/d' | sort -V | tail -1
}

updates=0
failures=0
skipped=0

# process every workflow file, in a stable order
while IFS= read -r file; do
	echo -e "${SHELL_BLUE}${file#"${WORKFLOW_DIR}/"}${SHELL_DEFAULT}"

	# collect the unique "owner/repo[/path]@ref" values used by the workflow
	# both "uses:" and the YAML list form "- uses:" are matched, but a commented
	# out step is not, as the "#" is not allowed before "uses:"
	mapfile -t refs < <(grep -hoE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^[:space:]]+' "${file}" \
		| awk '{ print $NF }' | sort -u)

	for ref in "${refs[@]}"; do
		action=${ref%%@*}
		current=${ref#*@}

		# local and Docker references have no upstream release to resolve
		if [[ ${action} == ./* || ${action} == docker://* ]]; then
			echo -e "  ${SHELL_BLUE}- ${action} skipped${SHELL_DEFAULT}"
			skipped=$((skipped + 1))
			continue
		fi

		# the SHA is always repo wide, even for an action in a sub directory
		repo=$(echo "${action}" | cut -d/ -f1,2)

		if [[ -z ${RESOLVED[${repo}]} ]]; then
			if ! latest=$(resolve_latest_release "${repo}") || [[ -z ${latest} ]]; then
				echo -e "  ${SHELL_RED}✗ ${action} could not resolve a release for ${repo}${SHELL_DEFAULT}"
				failures=$((failures + 1))
				continue
			fi
			RESOLVED[${repo}]=${latest}
		fi

		read -r tag sha <<< "${RESOLVED[${repo}]}"

		if [[ ${current} == "${sha}" ]]; then
			echo -e "  ✓ ${action}@${SHELL_GREEN}${tag}${SHELL_DEFAULT} already pinned"
			continue
		fi

		updates=$((updates + 1))
		echo -e "  ${SHELL_YELLOW}• ${action}@${current} -> ${sha} # ${tag}${SHELL_DEFAULT}"

		if ${WRITE_MODE}; then
			# escape the dots so they are not treated as regex wildcards
			escaped=${action//./\\.}
			sed -i -E "s|uses:([[:space:]]*)${escaped}@[^[:space:]]+.*|uses:\1${action}@${sha} # ${tag}|" "${file}"
		fi
	done
done < <(find "${WORKFLOW_DIR}" -maxdepth 1 -type f \( -name '*.yml' -or -name '*.yaml' \) | sort)

echo ''
if ((failures > 0)); then
	echo -e "${SHELL_RED}${failures} action(s) could not be resolved${SHELL_DEFAULT}"
fi
if ((skipped > 0)); then
	echo -e "${SHELL_BLUE}${skipped} local or Docker action(s) skipped${SHELL_DEFAULT}"
fi

if ((updates == 0)); then
	echo -e "${SHELL_GREEN}All actions are pinned to the commit SHA of their latest release${SHELL_DEFAULT}"
	((failures == 0)) || exit 1
	exit 0
fi

if ${WRITE_MODE}; then
	echo -e "${SHELL_GREEN}Updated ${updates} action(s); review the changes with: git diff .github/workflows${SHELL_DEFAULT}"
	((failures == 0)) || exit 1
	exit 0
fi

echo -e "${SHELL_YELLOW}${updates} action(s) need updating; re-run with --write to apply${SHELL_DEFAULT}"
exit 1
