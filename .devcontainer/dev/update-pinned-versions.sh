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
## A pin listed in PATCH_ONLY only follows the release series it is already on, so
## the patch releases are applied while a newer series is reported and left alone.
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

## pins that only follow the release series of the current pin, so the patch
## releases within that series are applied as usual, while a newer series is only
## reported and never written, not even by --write
## the series is the pin without its final component, so a pin of "1.26.6" follows
## "1.26.7" and "1.26.8" while "1.27.1" is only mentioned; moving the pin to the
## new series by hand is all that is needed to follow that series from then on
## Go is the case this exists for: a new "1.N" release changes the language
## toolchain across the whole repo, so it is upgraded deliberately, whereas a
## "1.N.P" release is a bug fix and security roll up that is always wanted
PATCH_ONLY=(
	"KNFSD_GOLANG_VERSION"
)

## pins that repeat a version as a literal, with no variable to match on, as
## "VARIABLE|FILE|LITERAL_PREFIX"; the version following the prefix is kept in
## step with the variable
## the prefix is a literal, matched anywhere on the line rather than only at its
## start, so a version inside an indented command is reached too; every line of
## the file carrying the prefix is rewritten, so one file can appear more than
## once when it repeats the version behind different prefixes
## the Go release is repeated as a download URL in the AMI build script and twice
## in the client metrics guide, and those drifted to 1.26.6 while the pin was on
## 1.26.8, which is what these entries prevent; the prerequisite prose in the
## client metrics guide and in the smoke tests README names the full release
## rather than a release series, so it is kept in step here as well
EXTRA_PINS=(
	"KNFSD_BATS_CORE_VERSION|image/resources/startup/tests/Dockerfile|FROM bats/bats:"
	"KNFSD_GOLANG_VERSION|docs/client-metrics.md|[Go "
	"KNFSD_GOLANG_VERSION|docs/client-metrics.md|https://go.dev/dl/go"
	"KNFSD_GOLANG_VERSION|docs/client-metrics.md|-xzf go"
	"KNFSD_GOLANG_VERSION|image/resources/scripts/10_build.sh|https://dl.google.com/go/go"
	"KNFSD_GOLANG_VERSION|image/smoke-tests/README.md|[Go "
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
# "include=all" returns the whole release history rather than only the two current
# release series, so the series a PATCH_ONLY pin sits on stays visible once it is
# no longer one of the two newest
GODEV_DL="https://go.dev/dl/?mode=json&include=all"
# fallback for the Go release when "go.dev" is unreachable; the tags are read with
# "git ls-remote" rather than the API, as the "golang/go" tag list is far longer
# than one API page and the API does not return it in version order
GOLANG_REPO="https://github.com/golang/go.git"
# tags requested per page; the newest tags are returned first
TAGS_PER_PAGE=100
# Docker Hub caps a page at 100 tags however many are asked for, and orders them by
# the last update rather than by version, so the pages are followed until enough
# plain version tags are collected, or the page cap is reached
DOCKERHUB_MAX_PAGES=10
DOCKERHUB_MIN_TAGS=10

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
	printf '    A PATCH_ONLY pin follows only the release series it is on; a newer\n'
	printf '    series is reported and upgraded by hand\n'
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

# print the stable versions from a list of versions on stdin, lowest first, so the
# caller can take the last line for the latest, or filter to one release series
function stable_versions() {
	grep -E "${STABLE_VERSION}" | sed -E 's/^v//' | sort -uV
}

# print the release series of a version, which is the version without its final
# component, so "1.26.6" gives "1.26" and "1.2.3.4" gives "1.2.3"
function version_series() {
	printf '%s\n' "${1%.*}"
}

# print the highest version of the given series from a list of versions on stdin,
# where a version is in the series when it is the series plus one more component,
# so "1.26" selects "1.26.8" but neither "1.26" nor "1.27.1"
# nothing is printed when the series has no such version
function highest_in_series() {
	local series=${1//./\\.}
	grep -E "^${series}\.[0-9]+$" | sort -V | tail -1
}

# print the stable releases of a GitHub repo, lowest first, without the "v" prefix
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
		grep -E "^${prefix}" <<< "${candidates}" | sed -E "s#^${prefix}##" | stable_versions
		return 0
	fi

	stable_versions <<< "${candidates}"
}

# print the stable, non yanked releases of a PyPI package, lowest first
function resolve_pypi() {
	local package=$1
	curl "${CURL_ARGS[@]}" "${PYPI_API}/${package}/json" \
		| jq -r '.releases | to_entries[]
			| select([.value[] | select(.yanked == false)] | length > 0)
			| .key' \
		| stable_versions
}

# print the stable tags of a Docker Hub repo, lowest first, without the "v" prefix
# a Docker Hub repo also carries floating tags such as "3.14" alongside the full
# "3.14.6" tag, so only the tags with the same number of parts as the current pin
# are considered, which keeps a floating tag from winning
# a repo may publish its tags with a "v" prefix, and may also carry variant tags
# such as "v2.1.20-debian", which are skipped as the pin is the plain tag
# the tags come back in "last updated" order, not in version order, and a page is
# capped at 100 tags, so a busy repo can fill a whole page with the variant tags of
# a single release and leave no plain tag on it at all: "library/python" carries
# close to 4000 tags and puts the plain "3.14.7" tag on page 2, behind a page of
# "-slim", "-alpine" and "-windowsservercore" variants. So the pages are followed
# until enough plain tags are collected, which costs one request for a small repo
function resolve_dockerhub() {
	local repo=$1 parts=$2
	local url="${DOCKERHUB_API}/${repo}/tags?page_size=${TAGS_PER_PAGE}"
	local page=0 response='' matched='' collected=''

	while [[ -n ${url} ]] && ((page < DOCKERHUB_MAX_PAGES)); do
		page=$((page + 1))
		response=$(curl "${CURL_ARGS[@]}" "${url}") || return 1

		matched=$(jq -r '.results[].name // empty' <<< "${response}" \
			| grep -E "^v?[0-9]+(\.[0-9]+){$((parts - 1))}$") || matched=''
		if [[ -n ${matched} ]]; then
			collected=$(printf '%s\n%s' "${collected}" "${matched}")
		fi

		if (($(grep -c . <<< "${collected}") >= DOCKERHUB_MIN_TAGS)); then
			break
		fi

		url=$(jq -r '.next // empty' <<< "${response}") || url=''
	done

	stable_versions <<< "${collected}"
}

# print the stable tags of a public Amazon ECR repo, lowest first
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
		| sort -uV
}

# print the stable Go releases, lowest first, without the "go" prefix
# "go.dev" is a plain HTTPS JSON endpoint, not the blocked Go module proxy, but if
# it cannot be reached the tags are read directly from the GitHub repo instead
function resolve_godev() {
	local versions=''

	versions=$(curl "${CURL_ARGS[@]}" "${GODEV_DL}" 2> /dev/null \
		| jq -r '.[] | select(.stable == true) | .version // empty' \
		| sed -E 's/^go//' \
		| stable_versions) || versions=''

	if [[ -n ${versions} ]]; then
		printf '%s\n' "${versions}"
		return 0
	fi

	git ls-remote --tags --refs "${GOLANG_REPO}" 2> /dev/null \
		| sed -E 's#.*refs/tags/##' \
		| grep -E '^go[0-9]+(\.[0-9]+){1,3}$' \
		| sed -E 's/^go//' \
		| stable_versions
}

# print the stable versions for the given source and reference, lowest first
function resolve_versions() {
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

# escape the ERE metacharacters in a literal so it can be interpolated into a
# "grep -E" or "sed -E" pattern, including "#", which is the sed delimiter used
# below; without this the dots in a prefix such as "https://dl.google.com/go/go"
# would be wildcards that also match an unrelated lookalike host
function ere_escape() {
	sed -E 's/[][(){}.*+?^$|\#]/\\&/g' <<< "$1"
}

# print every tracked file line that repeats a version after a literal prefix
# the prefix is matched anywhere on the line, not only at its start, so a version
# inside an indented command, such as a "curl" in a fenced code block, is found
function find_literal_pins() {
	local file=$1 prefix=$2
	local escaped
	escaped=$(ere_escape "${prefix}")
	git -C "${REPO_ROOT}" grep -nE -e "${escaped}[0-9]+(\.[0-9]+)+" -- "${file}" \
		| sed -E "s#^([^:]+):([0-9]+):.*${escaped}([0-9]+(\.[0-9]+)+).*#\1:\2:\3#"
}

# replace the version on a single line, leaving the rest of the line untouched so
# the "# https://..." discoverability comments survive (RULE 2)
# the version must not be flanked by a digit or a dot, so a pin of "1.27" is never
# matched inside "1.27.1"; a trailing dot is allowed only when a non-digit follows
# it, which reaches the version in a Go tarball name such as "go1.27.1.linux-amd64"
# while still refusing the "1.27.1" inside a longer "1.27.1.4"
function replace_version_on_line() {
	local file=$1 line=$2 old=$3 new=$4
	local path="${REPO_ROOT}/${file}"
	# escape the dots so they are not treated as regex wildcards
	local escaped=${old//./\\.}
	local mode
	# "sed -i" writes a new inode, which can drop the executable bit
	mode=$(stat -c '%a' "${path}")
	sed -i -E "${line}s#(^|[^0-9.])${escaped}([^0-9.]|\.[^0-9]|\$)#\1${new}\2#g" "${path}"
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
series_available=0
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
	# the highest pin is the floor for any rewrite, so converging a variable that is
	# pinned inconsistently moves the stale copies up to meet the rest, rather than
	# dragging the rest back down to the stale copy
	highest=${found[-1]}

	# match the shape of the highest pin so a floating registry tag cannot win
	parts=$(awk -F. '{ print NF }' <<< "${highest}")

	if ! resolved=$(resolve_versions "${source}" "${reference}" "${prefix}" "${parts}") \
		|| [[ -z ${resolved} ]]; then
		failures=$((failures + 1))
		echo -e "${SHELL_RED}✗ ${variable} could not resolve the latest version from ${source} (${reference})${SHELL_DEFAULT}"
		continue
	fi

	# the versions come back lowest first, so the last is the latest upstream
	latest=$(tail -1 <<< "${resolved}")

	## RULE 4: a PATCH_ONLY pin only follows its own release series, so the target
	## is the highest version of that series, and a newer series is only mentioned
	series=''
	series_latest=''
	if in_list "${variable}" "${PATCH_ONLY[@]}" && ((parts > 1)); then
		# the series comes from the highest pin, so one stale copy left behind on an
		# older series cannot pull the whole repo back onto that older series
		series=$(version_series "${highest}")
		series_latest=$(highest_in_series "${series}" <<< "${resolved}") || series_latest=''
		# upstream no longer lists the pinned series at all, so there is nothing
		# to compare against and any move off it has to be a deliberate one
		target=${series_latest:-${highest}}
	else
		target=${latest}
	fi

	## a rewrite must never move a pin backwards, whatever the series lookup said
	if version_gt "${highest}" "${target}"; then
		target=${highest}
	fi

	# a pin spread over several versions needs a rewrite whatever upstream says
	if ((${#found[@]} > 1)); then
		drifted=$((drifted + 1))
		echo -e "${SHELL_YELLOW}! ${variable} is pinned inconsistently: ${found[*]}${SHELL_DEFAULT}"
	fi

	if ! version_gt "${target}" "${current}"; then
		echo -e "✓ ${variable} ${SHELL_GREEN}${current}${SHELL_DEFAULT} is current"
	elif in_list "${variable}" "${NOTIFY_ONLY[@]}"; then
		## RULE 3: report the new release, but never rewrite the pin
		echo -e "${SHELL_BLUE}i ${variable} ${current} -> ${target} available, pin kept deliberately${SHELL_DEFAULT}"
		continue
	else
		updates=$((updates + 1))
		echo -e "${SHELL_YELLOW}• ${variable} ${current} -> ${target}${SHELL_DEFAULT}"
	fi

	# mention the newer series a PATCH_ONLY pin is deliberately not following
	if [[ -n ${series} ]] && version_gt "${latest}" "${target}"; then
		series_available=$((series_available + 1))
		echo -e "${SHELL_BLUE}i ${variable} ${latest} is available, outside the pinned ${series}.x series; upgrade it by hand${SHELL_DEFAULT}"
	fi

	if ${WRITE_MODE} && (version_gt "${target}" "${current}" || ((${#found[@]} > 1)) ); then
		apply_version "${variable}" "${target}"
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
if ((series_available > 0)); then
	echo -e "${SHELL_BLUE}${series_available} variable(s) have a newer release series available; upgrade by hand${SHELL_DEFAULT}"
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
