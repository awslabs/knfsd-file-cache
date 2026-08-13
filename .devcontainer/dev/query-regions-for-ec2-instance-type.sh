#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## Query all AWS regions for a given, single EC2 instance type/size and report the
## Availability Zones that offer it, then print a summary table of every region
## queried, grouped by "full", "partial", or "none" AZ availability.
## Only the "enabled" AWS regions in your AWS account are queried, so China &
## GovCloud (US) AWS regions are excluded.
## Set EXCLUDED_REGIONS below to skip specific AWS regions.
## Pass "--region" to query the AZs of a single AWS region instead.

## USAGE:
## ./query-regions-for-ec2-instance-type.sh                                    show the usage message
## ./query-regions-for-ec2-instance-type.sh <INSTANCE_TYPE>                    query every enabled region
## ./query-regions-for-ec2-instance-type.sh <INSTANCE_TYPE> --region <REGION>  query one region only

set -eo pipefail

SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_YELLOW='\033[0;33m'
SHELL_BLUE='\033[0;34m'
SHELL_DEFAULT='\033[0m'

# AWS regions to exclude from the batch query
# only applies to a query of every enabled region, as an explicit "--region" wins
# Example: EXCLUDED_REGIONS=("me-south-1" "me-central-1")
EXCLUDED_REGIONS=("me-south-1" "me-central-1")

# an instance type is a family, then a size, such as "c6in.16xlarge", "m5.metal"
# or "u7i.metal-24xl"
INSTANCE_TYPE_PATTERN='^[a-z][a-z0-9-]*\.(metal(-[0-9]+xl)?|[a-z0-9]+)$'

# a region is 2 or 3 lowercase parts, then a number, such as "eu-west-2",
# "ap-southeast-4" or "us-gov-west-1"
REGION_PATTERN='^[a-z]{2}(-[a-z]+){1,2}-[0-9]+$'

function usage() {
	printf 'Syntax: ./query-regions-for-ec2-instance-type.sh <INSTANCE_TYPE> [-r/--region <REGION>]\n'
	printf '    INSTANCE_TYPE:       the single EC2 instance type to look for\n'
	printf '    -r/--region REGION:  query the AZs of this AWS region only, instead of every enabled region\n'
	printf '    -h/--help:           show this message\n'
	printf '    Example: ./query-regions-for-ec2-instance-type.sh c6in.16xlarge\n'
	printf '    Example: ./query-regions-for-ec2-instance-type.sh c6in.16xlarge --region eu-west-2\n'
	printf 'Ensure AWS credentials/region are configured.\n'
	printf 'Edit EXCLUDED_REGIONS in this script to skip specific AWS regions.\n'
}

# a flag that takes a value must be followed by that value, not by another flag
function require_option_value() {
	local option=$1
	local value=${2:-}
	if [[ -z ${value} || ${value} == -* ]]; then
		echo -e "${SHELL_RED}ERROR: missing value for ${option}${SHELL_DEFAULT}" 1>&2
		usage 1>&2
		exit 2
	fi
}

# returns 0 (true) if the given region is in the EXCLUDED_REGIONS list
function is_excluded() {
	local candidate=$1
	local excluded
	for excluded in "${EXCLUDED_REGIONS[@]}"; do
		if [[ ${candidate} == "${excluded}" ]]; then
			return 0
		fi
	done
	return 1
}

# print the AZ letters of the given AZ names as "a,b,c", so the per region
# breakdown stays on one line
function az_letters() {
	local region=$1
	shift
	local az joined=""
	for az in "$@"; do
		joined+="${az#"${region}"},"
	done
	printf '%s' "${joined%,}"
}

# the summary table columns, shared by the header row and by every region row
function summary_row() {
	printf '%-16s %-8s %-5s %s' "$1" "$2" "$3" "$4"
}

# print the summary rows of one status, in the colour of that status
function print_rows() {
	local colour=$1
	shift
	local row
	for row in "$@"; do
		echo -e "${colour}${row}${SHELL_DEFAULT}"
	done
}

# print the totals for the run, then a table of every region queried, grouped by
# status in "full, partial, none" order, with the AZ letters of each region
function print_summary() {
	local region total
	local -a available missing full=() partial=() none=()
	local az_total=0 az_available=0

	for region in "${REGIONS_QUERIED[@]}"; do
		read -ra available <<< "${AVAILABLE_BY_REGION[${region}]:-}"
		read -ra missing <<< "${MISSING_BY_REGION[${region}]:-}"
		total=$((${#available[@]} + ${#missing[@]}))
		az_total=$((az_total + total))
		az_available=$((az_available + ${#available[@]}))

		if [[ ${#available[@]} -eq 0 ]]; then
			none+=("$(summary_row "${region}" "none" "0/${total}" \
				"✗ $(az_letters "${region}" "${missing[@]}")")")
		elif [[ ${#missing[@]} -eq 0 ]]; then
			full+=("$(summary_row "${region}" "full" "${total}/${total}" \
				"✓ $(az_letters "${region}" "${available[@]}")")")
		else
			partial+=("$(summary_row "${region}" "partial" "${#available[@]}/${total}" \
				"✓ $(az_letters "${region}" "${available[@]}")  ✗ $(az_letters "${region}" "${missing[@]}")")")
		fi
	done

	printf '\n'
	echo -e "Summary: ${SHELL_GREEN}${INSTANCE_TYPE}${SHELL_DEFAULT} in ${az_available}/${az_total} AZs," \
		"$((${#full[@]} + ${#partial[@]}))/${#REGIONS_QUERIED[@]} regions" \
		"(${#full[@]} full, ${#partial[@]} partial, ${#none[@]} none)"

	summary_row "REGION" "STATUS" "AZS" "AVAILABILITY"
	printf '\n'
	print_rows "${SHELL_BLUE}" "${full[@]}"
	print_rows "${SHELL_YELLOW}" "${partial[@]}"
	print_rows "${SHELL_RED}" "${none[@]}"

	if [[ ${#REGIONS_SKIPPED[@]} -gt 0 ]]; then
		echo "Excluded (${#REGIONS_SKIPPED[@]}): ${REGIONS_SKIPPED[*]}"
	fi
}

# an instance type is required, so a run with no flags only shows the usage
if [[ $# -eq 0 ]]; then
	usage 1>&2
	exit 2
fi

INSTANCE_TYPE=""
REGION=""

# the instance type is positional, so it can be given before or after "--region"
while [[ $# -gt 0 ]]; do
	case $1 in
		-h | -help | --help | help)
			usage
			exit 0
			;;
		-r | --region)
			require_option_value "$1" "${2:-}"
			REGION=$2
			shift 2
			;;
		-*)
			echo -e "${SHELL_RED}ERROR: unknown option: $1${SHELL_DEFAULT}" 1>&2
			usage 1>&2
			exit 2
			;;
		*)
			# only a single instance type is queried per run
			if [[ -n ${INSTANCE_TYPE} ]]; then
				echo -e "${SHELL_RED}ERROR: only one instance type can be queried: ${INSTANCE_TYPE} $1${SHELL_DEFAULT}" 1>&2
				usage 1>&2
				exit 2
			fi
			INSTANCE_TYPE=$1
			shift
			;;
	esac
done

if [[ -z ${INSTANCE_TYPE} ]]; then
	echo -e "${SHELL_RED}ERROR: no instance type given${SHELL_DEFAULT}" 1>&2
	usage 1>&2
	exit 2
fi

# check the required tools are installed
for binary in aws jq; do
	if ! command -v "${binary}" > /dev/null 2>&1; then
		echo -e "${SHELL_RED}ERROR: ${binary} not found in \$PATH${SHELL_DEFAULT}"
		exit 1
	fi
done

# check the instance type is shaped like a family and a size
if ! echo "${INSTANCE_TYPE}" | grep -qE "${INSTANCE_TYPE_PATTERN}"; then
	echo -e "${SHELL_RED}ERROR: invalid instance type: ${INSTANCE_TYPE}${SHELL_DEFAULT}"
	exit 1
fi

# check the region name is shaped like a region, then that the account can use it
if [[ -n ${REGION} ]]; then
	if ! echo "${REGION}" | grep -qE "${REGION_PATTERN}"; then
		echo -e "${SHELL_RED}ERROR: invalid AWS region: ${REGION}${SHELL_DEFAULT}"
		exit 1
	fi
	if ! aws ec2 describe-regions --region-names "${REGION}" > /dev/null 2>&1; then
		echo -e "${SHELL_RED}ERROR: not an enabled AWS region for this account: ${REGION}${SHELL_DEFAULT}"
		exit 1
	fi
fi

echo -e "Checking availability for instance type: ${SHELL_GREEN}${INSTANCE_TYPE}${SHELL_DEFAULT}"

# a single region is queried as given, so EXCLUDED_REGIONS is not consulted,
# otherwise every region enabled for this AWS account is queried
if [[ -n ${REGION} ]]; then
	echo -e "Limiting the query to region: ${SHELL_GREEN}${REGION}${SHELL_DEFAULT}"
	query_regions=${REGION}
else
	echo "Getting list of Availability Zones...(this will take a while)"
	query_regions=$(aws ec2 describe-regions --output text --query 'Regions[*].[RegionName]' | sort)
fi
all_az=()
# the regions actually queried, and those skipped, in the order they were seen
REGIONS_QUERIED=()
REGIONS_SKIPPED=()
# per region AZ names, space separated, keyed by region name
declare -A AVAILABLE_BY_REGION=()
declare -A MISSING_BY_REGION=()

# get all AZs for the regions being queried
while read -r region; do
	# skip any regions the user has flagged as excluded
	if [[ -z ${REGION} ]] && is_excluded "${region}"; then
		echo -e "${SHELL_RED}Skipping excluded region: ${region}${SHELL_DEFAULT}"
		REGIONS_SKIPPED+=("${region}")
		continue
	fi
	REGIONS_QUERIED+=("${region}")
	az_per_region=$(aws ec2 describe-availability-zones --region "${region}" --query 'AvailabilityZones[?ZoneType==`availability-zone`].[ZoneName]' --output text | sort)
	while read -r az; do
		all_az+=("${az}")
	done <<< "${az_per_region}"
done <<< "${query_regions}"

# get total number of AZs to check
counter=1
num_az=${#all_az[@]}

# check each AZ in each region
for az in "${all_az[@]}"; do
	echo -e "Checking AZ: ${az} (${counter}/${num_az})"

	# an AZ name is the region name plus a single letter suffix
	region=$(echo "${az}" | rev | cut -c 2- | rev)
	raw=$(aws ec2 describe-instance-type-offerings --filters "Name=location,Values=${az}" "Name=instance-type,Values=${INSTANCE_TYPE}" --location-type availability-zone --region "${region}")
	output=$(echo "${raw}" | jq -r '.InstanceTypeOfferings[0].InstanceType')

	# print if instance type is available in the AZ, and record it for the summary
	if [[ ${output} != "null" && -n ${output} ]]; then
		echo -e "${SHELL_BLUE}✓ ${az}${SHELL_DEFAULT}"
		AVAILABLE_BY_REGION[${region}]+="${az} "
	else
		echo -e "${SHELL_RED}✗ ${az};MISSING${SHELL_DEFAULT}"
		MISSING_BY_REGION[${region}]+="${az} "
	fi

	counter=$((counter + 1))
done

print_summary
