#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o pipefail

# terminal colors
SHELL_YELLOW='\033[0;33m'
SHELL_DEFAULT='\033[0m'

export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

# set the working directory to "/mnt/build"
cd "$(dirname "$0")"/../

# format the terminal for a command output
function begin_command() {
	echo -e "\n${SHELL_YELLOW}---- RUNNING: $1${SHELL_DEFAULT}"
	COMMAND_START_TIME=$(date +%s)
}

# format the terminal after command completion
function complete_command() {
	local end_time duration hours minutes seconds
	end_time=$(date +%s)
	duration=$((COMMAND_START_TIME > 0 ? end_time - COMMAND_START_TIME : 0))
	hours=$((duration / 3600))
	minutes=$(((duration % 3600) / 60))
	seconds=$((duration % 60))
	printf "${SHELL_YELLOW}---- DONE: %dh%02dm%02ds${SHELL_DEFAULT}\n" "$hours" "$minutes" "$seconds"
}

# git clone with retry, 10-50s delay between attempts
function git_clone() {
	local max_attempts=5
	local attempt
	local target="${!#}"
	if [[ "$target" == https://* ]] || [[ "$target" == git@* ]]; then
		target=$(basename "$target" .git)
	fi
	for attempt in $(seq 1 $max_attempts); do
		if git clone "$@"; then
			return 0
		fi
		echo "git clone failed (attempt $attempt/$max_attempts), retrying in ${attempt}0s..."
		rm -rf "$target"
		sleep $((attempt * 10))
	done
	echo "git clone failed after $max_attempts attempts"
	return 1
}

# remove unnecessary packages, reduce syslog noise
function remove_packages() (
	begin_command "Removing packages"
	apt-get -o DPkg::Lock::Timeout=60 purge -yq multipath-tools cryptsetup-initramfs
	complete_command
)

# install latest ena driver
function install_ena_driver() (
	begin_command "Installing ENA driver"
	git_clone --depth 1 --branch ena_linux_2.16.1 https://github.com/amzn/amzn-drivers.git amzn-drivers
	cd amzn-drivers/kernel/linux/ena/
	make
	# ena.ko OR ena.ko.zst
	ENA_FILE=$(find /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/ -name 'ena.ko*' -print0 | xargs -0 basename | head -n1)
	install -D -m 644 ena.ko /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/"${ENA_FILE}"
	update-initramfs -u
	complete_command
)

# cleanup the image before capture
function cleanup_image() (
	begin_command "Cleaning up image"
	apt-get -o DPkg::Lock::Timeout=60 autoremove -y
	apt-get -o DPkg::Lock::Timeout=60 clean -y
	rm -rf "/var/lib/apt/lists/*"
	find /root -mindepth 1 -delete
	truncate -s 0 /etc/machine-id
	complete_command
)

# run post build
remove_packages
install_ena_driver
cleanup_image

echo -e "\n${SHELL_YELLOW}---- SUCCESS: Finished post build image script${SHELL_DEFAULT}"
