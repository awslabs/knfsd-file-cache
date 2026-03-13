#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## Query all AWS regions for a given, single EC2 instance type/size
## Only "enabled" AWS regions in your AWS account are queried
## China & GovCloud (US) AWS regions are excluded

## USAGE:
## ./query-regions-for-ec2-instance-type.sh <INSTANCE_TYPE>
## ./query-regions-for-ec2-instance-type.sh c6in.2xlarge (default)

set -eo pipefail

SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_BLUE='\033[0;34m'
SHELL_DEFAULT='\033[0m'

# Default instance type, if not specified on cli
INSTANCE_TYPE=${1:-c6in.16xlarge}
# other good, generic instance types for packer build: c6i.16xlarge, m6i.16xlarge, c5.18xlarge, m5.16xlarge
# that are widely available in most AWS regions

echo -e "Checking availability for instance type: ${SHELL_GREEN}$INSTANCE_TYPE${SHELL_DEFAULT}"

# check if instance type is valid
if ! echo "${INSTANCE_TYPE}" | grep -qE '^[a-z][0-9]?[a-z]*\.(metal-[0-9]+xl|[a-z0-9]+)$'; then
	echo -e "${SHELL_RED}ERROR: invalid instance type: ${INSTANCE_TYPE}${SHELL_DEFAULT}"
	exit 1
fi

# get all regions
echo "Getting list of Availability Zones...(this may take a while)"
all_regions=$(aws ec2 describe-regions --output text --query 'Regions[*].[RegionName]' | sort)
all_az=()

# get all AZs for all regions
while read -r region; do
	az_per_region=$(aws ec2 describe-availability-zones --region "$region" --query 'AvailabilityZones[?ZoneType==`availability-zone`].[ZoneName]' --output text | sort)
	while read -r az; do
		all_az+=("$az")
	done <<< "$az_per_region"
done <<< "$all_regions"

# get total number of AZs to check
counter=1
num_az=${#all_az[@]}

# check each AZ in each region
for az in "${all_az[@]}"; do
	echo -e "Checking AZ: $az ($counter/$num_az)"

	region=$(echo "$az" | rev | cut -c 2- | rev)
	raw=$(aws ec2 describe-instance-type-offerings --filters "Name=location,Values=$az" "Name=instance-type,Values=$INSTANCE_TYPE" --location-type availability-zone --region "$region")
	output=$(echo "$raw" | jq -r '.InstanceTypeOfferings[0].InstanceType')

	# print if instance type is available in the AZ
	if [ "$output" != "null" ] && [ -n "$output" ]; then
		echo -e "${SHELL_BLUE}✓ $az${SHELL_DEFAULT}"
	else
		echo -e "${SHELL_RED}✗ $az;MISSING${SHELL_DEFAULT}"
	fi

	counter=$((counter + 1))
done
