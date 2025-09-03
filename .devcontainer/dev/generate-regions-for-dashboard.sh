#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## This script generates the list of regions for the "dashboard.json" file region selector
## It matches the displayed region order with the Amazon CloudWatch region order under "All metrics"

## USAGE:
## ./generate-regions-for-dashboard.sh

set -eo pipefail

echo '"values": ['

# get all regions
mapfile -t all_regions < <(aws ec2 describe-regions --all-regions --query 'Regions[].RegionName' --output text | tr '\t' '\n')

# function to get long name for a region
get_long_name() {
	local region=$1
	aws ssm get-parameter --name "/aws/service/global-infrastructure/regions/$region/longName" --query "Parameter.Value" --output text 2> /dev/null
}

# build arrays with region and long name pairs
us_region_data=()
other_region_data=()

for region in "${all_regions[@]}"; do
	long_name=$(get_long_name "$region")

	# skip if SSM lookup failed
	if ! long_name=$(get_long_name "$region") || [ -z "$long_name" ]; then
		continue
	fi

	# separate US regions from others
	if [[ $region =~ ^us- ]]; then
		us_region_data+=("$long_name|$region")
	else
		other_region_data+=("$long_name|$region")
	fi
done

# sort by long name (first part before |) using process substitution to avoid word splitting
readarray -t us_sorted < <(printf '%s\n' "${us_region_data[@]}" | sort)
readarray -t other_sorted < <(printf '%s\n' "${other_region_data[@]}" | sort)

# combine arrays with US regions first
all_sorted=("${us_sorted[@]}" "${other_sorted[@]}")

first_item=true
for entry in "${all_sorted[@]}"; do
	# split long_name and region
	long_name="${entry%|*}"
	region="${entry#*|}"

	# add comma separator (except for first item)
	if [ "$first_item" = false ]; then
		echo ","
	fi
	first_item=false

	# output JSON entry for "dashboard.json" file
	printf '  { "label": "%s %s", "value": "%s" }' "$long_name" "$region" "$region"
done

echo ''
echo ']'
