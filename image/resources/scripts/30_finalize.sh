#!/usr/bin/env bash

# Copyright 2020 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -o errexit

# terminal colors
SHELL_YELLOW='\033[0;33m'
SHELL_DEFAULT='\033[0m'

# cloud-init queries
REGION=$(cloud-init query region)
INSTANCE_ID=$(cloud-init query instance_id)

# update_status() updates the tag:"knfsd-file-cache:status" of the instance
# @param (str) $1 message
function update_status() {
	aws ec2 create-tags \
		--region "${REGION}" \
		--resources "${INSTANCE_ID}" \
		--tags "Key=knfsd-file-cache:status,Value=finalize: $1"
}

# print system info
echo -e "${SHELL_YELLOW}---- SYSTEM INFO${SHELL_DEFAULT}"
lsb_release -d -r -c | awk -F'\t' '{ printf "%-16s%s\n", $1, $2 }'
printf "%-16s${SHELL_YELLOW}%s${SHELL_DEFAULT}\n" "Kernel:" "$(uname -r)"

update_status "wait for AMI creation"

# clean cloud-init state/logs before AMI creation
cloud-init clean --logs --seed

echo -e "\n${SHELL_YELLOW}---- SUCCESS: Finished finalize image script${SHELL_DEFAULT}"
