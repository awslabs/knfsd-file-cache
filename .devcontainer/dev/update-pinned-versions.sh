#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## Check every "KNFSD_*_VERSION" pin in the repo against its upstream source and
## report, or rewrite, the pins that are behind the latest stable release.
## The pins are found by searching the whole repo, so a pin added to a new file is
## picked up without editing this script. Only the version number on a matched
## line is rewritten, so the "# https://..." discoverability comments are kept.
## Pre-release versions (rc, beta, dev and similar) are never suggested, and nor
## are the tags a repo flags upstream as a pre-release or a draft, which can look
## stable, such as a "v3.9.0" tagged while "v3.8.0" is still the latest release.
## Set GITHUB_COM_TOKEN to raise the GitHub API rate limit (60 to 5000 req/hour).

## NETWORK: only these hosts are contacted, and nothing here runs the "go" binary
##   api.github.com, pypi.org, hub.docker.com, public.ecr.aws, go.dev, github.com
## The Go module proxy ("proxy.golang.org") is deliberately never used, as it is
## blocked on the corporate network, which is why GOPROXY=direct is set for every
## build in this repo. So the Go tool versions are read straight from their GitHub
## repos, and the Go release itself falls back to a direct GitHub tag listing if
## "go.dev" cannot be reached. Do not "simplify" any of this back to the proxy or
## to "pkg.go.dev", even though a pin comment points at "pkg.go.dev" for browsing.

## USAGE:
## ./update-pinned-versions.sh                           report the available updates
## ./update-pinned-versions.sh --write                   rewrite the pins in place
## ./update-pinned-versions.sh --write KNFSD_UV_VERSION  limit the run to one variable

set -eo pipefail

SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_YELLOW='\033[0;33m'
SHELL_BLUE='\033[0;34m'
SHELL_DEFAULT='\033[0m'

## upstream sources, one per variable: "VARIABLE|SOURCE|REFERENCE[|TAG_PREFIX]"
## SOURCE is one of: github, pypi, dockerhub, ecr-public, godev
## the REFERENCE matches the "# https://..." comment above (or beside) each pin
## TAG_PREFIX limits a github lookup to the tags carrying that prefix, which is
## needed for a repo that releases several modules from the same tag namespace
VERSION_SOURCES=(
	"KNFSD_ALPINE_VERSION|dockerhub|library/alpine"
	"KNFSD_BATS_CORE_VERSION|github|bats-core/bats-core"
	"KNFSD_BLACK_VERSION|pypi|black"
	"KNFSD_BOTO3_VERSION|pypi|boto3"
	"KNFSD_CHECKOV_VERSION|dockerhub|bridgecrew/checkov"
	"KNFSD_CODESPELL_VERSION|pypi|codespell"
	"KNFSD_DLV_VERSION|github|go-delve/delve"
	"KNFSD_DYNAMODB_VERSION|ecr-public|aws-dynamodb-local/aws-dynamodb-local"
	"KNFSD_EDITORCONFIG_VERSION|github|editorconfig-checker/editorconfig-checker"
	"KNFSD_GOLANGCI_LINT_VERSION|github|golangci/golangci-lint"
	"KNFSD_GOLANG_VERSION|godev|go"
	"KNFSD_GOPLS_VERSION|github|golang/tools|gopls/v"
	"KNFSD_GOSEC_VERSION|github|securego/gosec"
	"KNFSD_GOVULNCHECK_VERSION|github|golang/vuln"
	"KNFSD_IAMLIVE_VERSION|github|iann0036/iamlive"
	"KNFSD_KANIKO_VERSION|github|GoogleContainerTools/kaniko"
	"KNFSD_KICS_VERSION|dockerhub|checkmarx/kics"
	"KNFSD_MKDOCS_MATERIAL_VERSION|pypi|mkdocs-material"
	"KNFSD_MKDOCS_SAME_DIR_VERSION|pypi|mkdocs-same-dir"
	"KNFSD_MKDOCS_VERSION|pypi|mkdocs"
	"KNFSD_MYPY_VERSION|pypi|mypy"
	"KNFSD_PACKER_VERSION|github|hashicorp/packer"
	"KNFSD_PRECOMMIT_VERSION|pypi|pre-commit"
	"KNFSD_PYLINT_VERSION|pypi|pylint"
	"KNFSD_PYTHON_VERSION|dockerhub|library/python"
	"KNFSD_SEMGREP_VERSION|pypi|semgrep"
	"KNFSD_SESSION_MANAGER_PLUGIN_VERSION|github|aws/session-manager-plugin"
	"KNFSD_SHELLCHECK_PY_VERSION|pypi|shellcheck-py"
	"KNFSD_SHELLCHECK_VERSION|github|koalaman/shellcheck"
	"KNFSD_SHFMT_VERSION|github|mvdan/sh"
	"KNFSD_TFLINT_VERSION|github|terraform-linters/tflint"
	"KNFSD_TRIVY_VERSION|github|aquasecurity/trivy"
	"KNFSD_TZUPDATE_VERSION|pypi|tzupdate"
	"KNFSD_UV_VERSION|github|astral-sh/uv"
)

## never queried upstream and never reported as out of date, so a newer release
## is not even mentioned; a pin that has drifted from the frozen version is an
## error, and --write restores it
FROZEN_VERSIONS=(
	"KNFSD_TERRAFORM_VERSION|1.2.9"
)

## deliberate pins that are still queried upstream and reported, so a new
## release is visible, but are never rewritten, not even by --write
NOTIFY_ONLY=(
	"KNFSD_MKDOCS_MATERIAL_VERSION"
	"KNFSD_MKDOCS_SAME_DIR_VERSION"
	"KNFSD_MKDOCS_VERSION"
)

## pins that repeat a version as a literal, with no variable to match on, as
## "VARIABLE|FILE|LITERAL_PREFIX"; the version following the prefix is kept in
## step with the variable
EXTRA_PINS=(
	"KNFSD_BATS_CORE_VERSION|image/resources/startup/tests/Dockerfile|FROM bats/bats:"
)

## a stable version is 2 to 4 dot separated numbers, with an optional "v" prefix,
## which excludes pre-release tags such as v1.2.3-rc1, 2.0.0b1 or 1.2.3.dev4
## a tag can match this and still be a pre-release upstream, so resolve_github also
## drops the tags GitHub flags as a pre-release or a draft
STABLE_VERSION='^v?[0-9]+(\.[0-9]+){1,3}$'

GITHUB_API="https://api.github.com"
PYPI_API="https://pypi.org/pypi"
DOCKERHUB_API="https://hub.docker.com/v2/repositories"
ECR_PUBLIC="https://public.ecr.aws"
GODEV_DL="https://go.dev/dl/?mode=json"
# fallback for the Go release when "go.dev" is unreachable; the tags are read with
# "git ls-remote" rather than the API, as the "golang/go" tag list is far longer
# than one API page and the API does not return it in version order
GOLANG_REPO="https://github.com/golang/go.git"
# tags requested per page; the newest tags are returned first
TAGS_PER_PAGE=100

# never consult the Go module proxy, which is blocked on the corporate network;
# nothing here runs the "go" binary, so this is belt and braces for any future
# edit that adds a "go list -m" style lookup
export GOPROXY=direct
# never prompt for git credentials, so an unreachable host fails fast
export GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

function usage() {
	printf 'Syntax: ./update-pinned-versions.sh [-w/--write] [VARIABLE]\n'
	printf '    Default:    report the pins that are behind their latest stable release\n'
	printf '    -w/--write: rewrite the outdated pins in place\n'
	printf '    VARIABLE:   limit the run to one KNFSD_*_VERSION variable\n'
	printf '    Example: ./update-pinned-versions.sh --write KNFSD_UV_VERSION\n'
}

# check for help flags
if [[ $1 == '-h' || $1 == '--help' || $1 == 'help' ]]; then
	usage
	exit 0
fi

# check for write flag, then for an optional single variable to check
WRITE_MODE=false
if [[ $1 == '-w' || $1 == '--write' ]]; then
	WRITE_MODE=true
	shift
fi

ONLY_VARIABLE=$1
if [[ -n ${ONLY_VARIABLE} && ${ONLY_VARIABLE} != KNFSD_*_VERSION ]]; then
	echo -e "${SHELL_RED}ERROR: not a KNFSD_*_VERSION variable: ${ONLY_VARIABLE}${SHELL_DEFAULT}" 1>&2
	usage 1>&2
	exit 2
fi

# check the required tools are installed
for binary in curl git jq; do
	if ! command -v "${binary}" > /dev/null 2>&1; then
		echo -e "${SHELL_RED}ERROR: ${binary} not found in \$PATH${SHELL_DEFAULT}"
		exit 1
	fi
done

if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
	echo -e "${SHELL_RED}ERROR: not a git repository: ${REPO_ROOT}${SHELL_DEFAULT}"
	exit 1
fi

# authenticate when a token is available to avoid the low anonymous rate limit
CURL_ARGS=(--silent --show-error --fail --location --max-time 30)
GITHUB_ARGS=("${CURL_ARGS[@]}" --header "Accept: application/vnd.github+json")
if [[ -n ${GITHUB_COM_TOKEN} ]]; then
	GITHUB_ARGS+=(--header "Authorization: Bearer ${GITHUB_COM_TOKEN}")
fi

# returns 0 (true) if the given variable is in the given list of variables
function in_list() {
	local candidate=$1 entry
	shift
	for entry in "$@"; do
		if [[ ${entry} == "${candidate}" ]]; then
			return 0
		fi
	done
	return 1
}

# returns 0 (true) if version $1 is newer than version $2
function version_gt() {
	[[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1) == "$1" ]]
}

# print the highest stable version from a list of versions on stdin
function highest_stable() {
	grep -E "${STABLE_VERSION}" | sed -E 's/^v//' | sort -V | tail -1
}

# print the latest stable release of a GitHub repo, without the "v" prefix
# both the tags and the published releases are checked, then the highest is taken,
# as neither is reliable on its own: a repo can tag a version it never publishes as
# a release ("golang/vuln" tags v1.6.0 while its latest release is v1.1.4), and a
# repo can carry stale releases alongside live tags
# the tags flagged upstream as a pre-release, or as an unpublished draft, are
# dropped first, because such a tag can still look stable to STABLE_VERSION, as
# with the "v3.9.0" pre-release tagged while "v3.8.0" is the latest release of
# "editorconfig-checker"; the release list is fetched in place of the
# "/releases/latest" endpoint, so for the common case the flags are free, and the
# newest releases are returned first, which is where a pre-release always sits
# a failed release lookup is not fatal, as the tags alone still give an answer
function resolve_github() {
	local repo=$1 prefix=$2
	local tags='' releases='' stable='' unstable='' candidates=''

	tags=$(curl "${GITHUB_ARGS[@]}" \
		"${GITHUB_API}/repos/${repo}/tags?per_page=${TAGS_PER_PAGE}" \
		| jq -r '.[].name // empty') || return 1

	releases=$(curl "${GITHUB_ARGS[@]}" \
		"${GITHUB_API}/repos/${repo}/releases?per_page=${TAGS_PER_PAGE}") || releases=''

	if [[ -n ${releases} ]]; then
		stable=$(jq -r '.[] | select(.prerelease != true and .draft != true)
			| .tag_name // empty' <<< "${releases}") || stable=''
		unstable=$(jq -r '.[] | select(.prerelease == true or .draft == true)
			| .tag_name // empty' <<< "${releases}") || unstable=''
	fi

	candidates=$(printf '%s\n%s\n' "${tags}" "${stable}")
	if [[ -n ${unstable} ]]; then
		# whole line, fixed string matching, as a tag is not a regex
		candidates=$(grep -Fxv -f <(printf '%s\n' "${unstable}") <<< "${candidates}") \
			|| candidates=''
	fi

	if [[ -n ${prefix} ]]; then
		# a prefixed repo publishes several modules from one tag namespace, so
		# only the tags carrying the prefix of the wanted module are considered
		grep -E "^${prefix}" <<< "${candidates}" | sed -E "s#^${prefix}##" | highest_stable
		return 0
	fi

	highest_stable <<< "${candidates}"
}

# print the latest stable, non yanked release of a PyPI package
function resolve_pypi() {
	local package=$1
	curl "${CURL_ARGS[@]}" "${PYPI_API}/${package}/json" \
		| jq -r '.releases | to_entries[]
			| select([.value[] | select(.yanked == false)] | length > 0)
			| .key' \
		| highest_stable
}

# print the highest stable tag of a Docker Hub repo, without the "v" prefix
# a Docker Hub repo also carries floating tags such as "3.14" alongside the full
# "3.14.6" tag, so only the tags with the same number of parts as the current pin
# are considered, which keeps a floating tag from winning
# a repo may publish its tags with a "v" prefix, and may also carry variant tags
# such as "v2.1.20-debian", which are skipped as the pin is the plain tag
function resolve_dockerhub() {
	local repo=$1 parts=$2
	curl "${CURL_ARGS[@]}" "${DOCKERHUB_API}/${repo}/tags?page_size=${TAGS_PER_PAGE}" \
		| jq -r '.results[].name // empty' \
		| grep -E "^v?[0-9]+(\.[0-9]+){$((parts - 1))}$" \
		| sed -E 's/^v//' \
		| sort -V | tail -1
}

# print the highest stable tag of a public Amazon ECR repo
function resolve_ecr_public() {
	local repo=$1 parts=$2
	local token=''

	token=$(curl "${CURL_ARGS[@]}" \
		"${ECR_PUBLIC}/token/?scope=repository:${repo}:pull&service=public.ecr.aws" \
		| jq -r '.token // empty') || return 1
	[[ -n ${token} ]] || return 1

	curl "${CURL_ARGS[@]}" --header "Authorization: Bearer ${token}" \
		"${ECR_PUBLIC}/v2/${repo}/tags/list" \
		| jq -r '.tags[] // empty' \
		| grep -E "^[0-9]+(\.[0-9]+){$((parts - 1))}$" \
		| sort -V | tail -1
}

# print the current stable Go release, without the "go" prefix
# "go.dev" is a plain HTTPS JSON endpoint, not the blocked Go module proxy, but if
# it cannot be reached the tags are read directly from the GitHub repo instead
function resolve_godev() {
	local latest=''

	latest=$(curl "${CURL_ARGS[@]}" "${GODEV_DL}" 2> /dev/null \
		| jq -r '.[] | select(.stable == true) | .version // empty' \
		| sed -E 's/^go//' \
		| highest_stable) || latest=''

	if [[ -n ${latest} ]]; then
		printf '%s\n' "${latest}"
		return 0
	fi

	git ls-remote --tags --refs "${GOLANG_REPO}" 2> /dev/null \
		| sed -E 's#.*refs/tags/##' \
		| grep -E '^go[0-9]+(\.[0-9]+){1,3}$' \
		| sed -E 's/^go//' \
		| sort -V | tail -1
}

# print the latest stable version for the given source and reference
function resolve_latest() {
	local source=$1 reference=$2 prefix=$3 parts=$4

	case ${source} in
		github)
			resolve_github "${reference}" "${prefix}"
			;;
		pypi)
			resolve_pypi "${reference}"
			;;
		dockerhub)
			resolve_dockerhub "${reference}" "${parts}"
			;;
		ecr-public)
			resolve_ecr_public "${reference}" "${parts}"
			;;
		godev)
			resolve_godev
			;;
		*)
			return 1
			;;
	esac
}

# print every tracked file that pins the given variable, as "FILE:LINE:VERSION"
# "git grep" is used so ignored paths, such as the built docs site, are skipped
function find_pins() {
	local variable=$1
	git -C "${REPO_ROOT}" grep -nE "(^|[^A-Z_])${variable}[[:space:]]*[:=][[:space:]]*\"?[0-9]+(\.[0-9]+)+\"?" \
		| sed -E "s#^([^:]+):([0-9]+):.*${variable}[[:space:]]*[:=][[:space:]]*\"?([0-9]+(\.[0-9]+)+)\"?.*#\1:\2:\3#"
}

# print every tracked file line that repeats a version after a literal prefix
function find_literal_pins() {
	local file=$1 prefix=$2
	git -C "${REPO_ROOT}" grep -nE "^${prefix}[0-9]+(\.[0-9]+)+" -- "${file}" \
		| sed -E "s#^([^:]+):([0-9]+):${prefix}([0-9]+(\.[0-9]+)+).*#\1:\2:\3#"
}

# replace the version on a single line, leaving the rest of the line untouched so
# the "# https://..." discoverability comments survive (RULE 2)
function replace_version_on_line() {
	local file=$1 line=$2 old=$3 new=$4
	local path="${REPO_ROOT}/${file}"
	# escape the dots so they are not treated as regex wildcards
	local escaped=${old//./\\.}
	local mode
	# "sed -i" writes a new inode, which can drop the executable bit
	mode=$(stat -c '%a' "${path}")
	sed -i -E "${line}s#(^|[^0-9.])${escaped}([^0-9.]|$)#\1${new}\2#g" "${path}"
	chmod "${mode}" "${path}"
}

# rewrite every pin of a variable to the target version, printing each file
function apply_version() {
	local variable=$1 target=$2
	local pin file line current

	while IFS=: read -r file line current; do
		[[ -n ${file} ]] || continue
		if [[ ${current} == "${target}" ]]; then
			continue
		fi
		replace_version_on_line "${file}" "${line}" "${current}" "${target}"
		echo -e "      ${SHELL_BLUE}${file}:${line}${SHELL_DEFAULT} ${current} -> ${target}"
	done < <(find_pins "${variable}")

	# keep any literal repeat of the same version in step
	for pin in "${EXTRA_PINS[@]}"; do
		IFS='|' read -r pin_variable pin_file pin_prefix <<< "${pin}"
		[[ ${pin_variable} == "${variable}" ]] || continue
		while IFS=: read -r file line current; do
			[[ -n ${file} && ${current} != "${target}" ]] || continue
			replace_version_on_line "${file}" "${line}" "${current}" "${target}"
			echo -e "      ${SHELL_BLUE}${file}:${line}${SHELL_DEFAULT} ${current} -> ${target}"
		done < <(find_literal_pins "${pin_file}" "${pin_prefix}")
	done
}

# print the distinct versions a variable is pinned to across the repo
function pinned_versions() {
	local variable=$1
	{
		find_pins "${variable}" | cut -d: -f3
		for pin in "${EXTRA_PINS[@]}"; do
			IFS='|' read -r pin_variable pin_file pin_prefix <<< "${pin}"
			[[ ${pin_variable} == "${variable}" ]] || continue
			find_literal_pins "${pin_file}" "${pin_prefix}" | cut -d: -f3
		done
	} | sort -uV
}

updates=0
drifted=0
failures=0
frozen_errors=0
# every variable this script knows about, used to reject an unknown VARIABLE
KNOWN_VARIABLES=()

echo -e "Checking pinned versions in: ${SHELL_BLUE}${REPO_ROOT}${SHELL_DEFAULT}"
if [[ -z ${GITHUB_COM_TOKEN} ]]; then
	echo -e "${SHELL_YELLOW}- GITHUB_COM_TOKEN not set; using the 60 req/hour anonymous rate limit${SHELL_DEFAULT}"
fi
echo ''

## RULE 1: verify the frozen pins have not drifted, without querying upstream
for frozen in "${FROZEN_VERSIONS[@]}"; do
	IFS='|' read -r variable required <<< "${frozen}"
	KNOWN_VARIABLES+=("${variable}")
	if [[ -n ${ONLY_VARIABLE} && ${ONLY_VARIABLE} != "${variable}" ]]; then
		continue
	fi

	mapfile -t found < <(pinned_versions "${variable}")
	if ((${#found[@]} == 0)); then
		echo -e "${SHELL_YELLOW}? ${variable} frozen at ${required}, but no pin was found${SHELL_DEFAULT}"
		continue
	fi

	if ((${#found[@]} == 1)) && [[ ${found[0]} == "${required}" ]]; then
		echo -e "✓ ${variable} ${SHELL_GREEN}frozen at ${required}${SHELL_DEFAULT}"
		continue
	fi

	frozen_errors=$((frozen_errors + 1))
	echo -e "${SHELL_RED}✗ ${variable} must stay frozen at ${required}, found: ${found[*]}${SHELL_DEFAULT}"
	if ${WRITE_MODE}; then
		apply_version "${variable}" "${required}"
		frozen_errors=$((frozen_errors - 1))
	fi
done

## query each remaining variable upstream and compare against the pin
for entry in "${VERSION_SOURCES[@]}"; do
	IFS='|' read -r variable source reference prefix <<< "${entry}"
	KNOWN_VARIABLES+=("${variable}")

	if [[ -n ${ONLY_VARIABLE} && ${ONLY_VARIABLE} != "${variable}" ]]; then
		continue
	fi

	mapfile -t found < <(pinned_versions "${variable}")
	if ((${#found[@]} == 0)); then
		echo -e "${SHELL_YELLOW}? ${variable} has no pin in the repo; remove it from VERSION_SOURCES${SHELL_DEFAULT}"
		continue
	fi

	# the lowest pin is the one to compare, so a partial update is still caught
	current=${found[0]}

	# match the shape of the current pin so a floating registry tag cannot win
	parts=$(awk -F. '{ print NF }' <<< "${current}")

	if ! latest=$(resolve_latest "${source}" "${reference}" "${prefix}" "${parts}") \
		|| [[ -z ${latest} ]]; then
		failures=$((failures + 1))
		echo -e "${SHELL_RED}✗ ${variable} could not resolve the latest version from ${source} (${reference})${SHELL_DEFAULT}"
		continue
	fi

	# a pin spread over several versions needs a rewrite whatever upstream says
	if ((${#found[@]} > 1)); then
		drifted=$((drifted + 1))
		echo -e "${SHELL_YELLOW}! ${variable} is pinned inconsistently: ${found[*]}${SHELL_DEFAULT}"
	fi

	if ! version_gt "${latest}" "${current}"; then
		echo -e "✓ ${variable} ${SHELL_GREEN}${current}${SHELL_DEFAULT} is current"
	elif in_list "${variable}" "${NOTIFY_ONLY[@]}"; then
		## RULE 3: report the new release, but never rewrite the pin
		echo -e "${SHELL_BLUE}i ${variable} ${current} -> ${latest} available, pin kept deliberately${SHELL_DEFAULT}"
		continue
	else
		updates=$((updates + 1))
		echo -e "${SHELL_YELLOW}• ${variable} ${current} -> ${latest}${SHELL_DEFAULT}"
	fi

	if ${WRITE_MODE} && (version_gt "${latest}" "${current}" || ((${#found[@]} > 1))); then
		apply_version "${variable}" "${latest}"
	fi
done

echo ''
if [[ -n ${ONLY_VARIABLE} ]] && ! in_list "${ONLY_VARIABLE}" "${KNOWN_VARIABLES[@]}"; then
	echo -e "${SHELL_RED}ERROR: unknown variable: ${ONLY_VARIABLE}${SHELL_DEFAULT}" 1>&2
	echo -e "${SHELL_BLUE}Add it to VERSION_SOURCES to have it checked${SHELL_DEFAULT}" 1>&2
	exit 2
fi

if ((failures > 0)); then
	echo -e "${SHELL_RED}${failures} variable(s) could not be resolved upstream${SHELL_DEFAULT}"
fi
if ((frozen_errors > 0)); then
	echo -e "${SHELL_RED}${frozen_errors} frozen pin(s) have drifted; re-run with --write to restore${SHELL_DEFAULT}"
fi
if ((drifted > 0)); then
	echo -e "${SHELL_YELLOW}${drifted} variable(s) are pinned to more than one version${SHELL_DEFAULT}"
fi

if ${WRITE_MODE}; then
	echo -e "${SHELL_GREEN}Review the changes with: git diff${SHELL_DEFAULT}"
	((failures == 0 && frozen_errors == 0)) || exit 1
	exit 0
fi

if ((updates > 0)); then
	echo -e "${SHELL_YELLOW}${updates} version(s) can be updated; re-run with --write to apply${SHELL_DEFAULT}"
	exit 1
fi

if ((failures > 0 || frozen_errors > 0 || drifted > 0)); then
	exit 1
fi

echo -e "${SHELL_GREEN}All pinned versions are current${SHELL_DEFAULT}"
