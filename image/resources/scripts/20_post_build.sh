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

# install latest ena driver
function install_ena_driver() (
	begin_command "Installing ENA driver"
	apt-get install -yq make gcc
	git clone --depth 1 --branch ena_linux_2.16.1 https://github.com/amzn/amzn-drivers
	cd amzn-drivers/kernel/linux/ena/
	make
	# ena.ko OR ena.ko.zst
	ENA_FILE=$(find /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/ -name 'ena.ko*' -print0 | xargs -0 basename | head -n1)
	install -D -m 644 ena.ko /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/"${ENA_FILE}"
	update-initramfs -u
	complete_command
)

# remove unnecessary packages, reduce syslog noise
function remove_packages() (
	begin_command "Removing packages"
	apt-get purge -yq multipath-tools
	complete_command
)

# cleanup the image before capture
function cleanup_image() (
	begin_command "Cleaning up image"
	apt-get autoremove -y
	apt-get clean -y
	rm -rf "/var/lib/apt/lists/*"
	find /root -mindepth 1 -delete
	truncate -s 0 /etc/machine-id
	complete_command
)

# run post build
install_ena_driver
remove_packages
cleanup_image

echo -e "\n${SHELL_YELLOW}---- SUCCESS: Finished post build image script${SHELL_DEFAULT}"
