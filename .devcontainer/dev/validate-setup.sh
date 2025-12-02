#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -eo pipefail

SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_YELLOW='\033[0;33m'
SHELL_BLUE='\033[0;34m'
SHELL_DEFAULT='\033[0m'
USERNAME="ubuntu"
VERSION="1.1.0-alpha.17"

# List of binaries to check
binaries=(
	"awk"
	"curl"
	"cut"
	"dig"
	"dpkg"
	"echo"
	"file"
	"gcc"
	"getopt"
	"git"
	"grep"
	"htop"
	"jq"
	"less"
	"make"
	"man"
	"nfstrace"
	"pip"
	"sed"
	"set"
	"ssh"
	"sudo"
	"tar"
	"unzip"
	"vim"
	"wc"
	"xargs"
	"aws"
	"bats"
	"black"
	"checkov"
	"codespell"
	"docker"
	"editorconfig-checker"
	"git"
	"go"
	"golangci-lint"
	"packer"
	"pre-commit"
	"semgrep"
	"shellcheck"
	"shfmt"
	"terraform"
	"terragrunt"
	"tflint"
	"tfsec"
	"trivy"
	"tzupdate"
)

# Function to check if a binary exists in $PATH and get its version
function check_binary() {
	local binary=$1
	if command -v "$binary" &> /dev/null; then
		echo -e "✓ $binary ${SHELL_GREEN}found${SHELL_DEFAULT}"
	else
		echo -e "${SHELL_RED}✗ $binary not found in $PATH${SHELL_DEFAULT}"
	fi
}

# Check each binary in the list
for binary in "${binaries[@]}"; do
	check_binary "$binary"
done

# List of environment variables to check
env_vars=(
	"CI"
	"LANG"
	"GITHUB_COM_TOKEN"
	"PACKER_GITHUB_API_TOKEN"
	"SHELL"
	"GOLANGCI_LINT_CACHE"
	"HOME"
	"TF_APPEND_USER_AGENT"
)

# List of expected values for each environment variable
expected_values=(
	"devcontainer"
	"en_US.UTF-8"
	"^ghp_[a-zA-Z0-9]{36}$"
	"^ghp_[a-zA-Z0-9]{36}$"
	"/bin/bash"
	"/home/${USERNAME}/.cache/golangci-lint"
	"/home/${USERNAME}"
	"AWSSOLUTION/SO9129/${VERSION}"
)

# Function to check an environment variable
function check_env_var() {
	local var_name=$1
	local expected_value=$2
	local actual_value="${!var_name}"

	if [ -z "$actual_value" ]; then
		echo -e "${SHELL_RED}✗ $var_name is not set${SHELL_DEFAULT}"
	elif [[ $actual_value =~ $expected_value ]]; then
		echo -e "✓ $var_name is set to: ${SHELL_GREEN}$actual_value${SHELL_DEFAULT}"
	else
		echo -e "${SHELL_YELLOW}✗ $var_name is set to: $actual_value (expected format: $expected_value)${SHELL_DEFAULT}"
	fi
}

# Check each environment variable in the list
for i in "${!env_vars[@]}"; do
	check_env_var "${env_vars[$i]}" "${expected_values[$i]}"
done

# Function to check if running on EC2 instance & IMDSv2 is working
function main() {
	# Check if running on EC2 instance
	sys_vendor="/sys/devices/virtual/dmi/id/sys_vendor"
	if [ ! -f "${sys_vendor}" ] || ! grep -q "Amazon" "${sys_vendor}"; then
		echo -e "${SHELL_BLUE}- Not running on Amazon EC2. IMDSv2 check skipped${SHELL_DEFAULT}"
		exit 0
	fi

	# Fetch the IMDSv2 token
	local token
	if ! token=$(curl -s -m 5 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); then
		echo -e "${SHELL_RED}✗ Failed to get IMDSv2 token. Exit code: $?${SHELL_DEFAULT}"
		exit 1
	fi

	if [ -z "${token}" ]; then
		echo -e "${SHELL_RED}✗ Failed to fetch IMDSv2 token${SHELL_DEFAULT}"
		exit 1
	fi

	# Compare the instance ID with the IMDSv2 ID
	local local_id
	local_id=$(cat /sys/devices/virtual/dmi/id/board_asset_tag)
	local imds_id
	imds_id=$(curl -s -m 5 -H "X-aws-ec2-metadata-token: ${token}" http://169.254.169.254/latest/meta-data/instance-id)
	if [ "${local_id}" != "${imds_id}" ]; then
		echo -e "${SHELL_RED}✗ IMDSv2 check failed. Ensure IMDSv2 is configured correctly${SHELL_DEFAULT}"
		exit 1
	fi

	echo -e "✓ Running on EC2 and ${SHELL_GREEN}IMDSv2 working correctly${SHELL_DEFAULT}"
}

main
