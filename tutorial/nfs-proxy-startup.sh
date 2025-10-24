#!/usr/bin/env bash

# Copyright 2021 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This script is a simplified version of the main "proxy-startup.sh" script from the
# Terraform module for the purpose of the tutorial. This script has limited
# features and does not support configuring the source server.
# This script is designed to run on an AWS EC2 i4i.xlarge instance only using
# local NVMe instance store for FS-Cache.

# exit immediately if a command exits with a non-zero status
set -o errexit
set -o pipefail
shopt -s lastpipe

# env vars
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive

MOUNT_OPTIONS="vers=3,nconnect=16,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc"

# install ENA driver
apt-get update
apt-get install -yq make gcc
cd /tmp
git clone https://github.com/amzn/amzn-drivers
cd amzn-drivers/kernel/linux/ena/
make
ENA_FILE=$(find /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/ -name 'ena.ko*' -print0 | xargs -0 basename | head -n1)
install -D -m 644 ena.ko /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/"${ENA_FILE}"
update-initramfs -u
modprobe ena

# install NFS server, client, and FS-Cache packages
apt-get install -yq rpcbind nfs-kernel-server cachefilesd nfs-common

# has_fs() checks if a path has a filesystem
function has_fs() {
	lsblk -no FSTYPE "$1" | grep -q .
}

# start_fs_cache() starts the FS-Cache service
function start_fs_cache() {
	if ! systemctl start cachefilesd; then
		# Sometimes cachefilesd reports an error when starting but does
		# start correctly. This is likely an error in the init script or
		# with how systemd integrates with init scripts.
		# Trying a second time normally works. If you check
		# /proc/fs/fscache/caches the cache is actually active.
		if ! systemctl start cachefilesd; then
			# Second attempt failed, this is now a genuine error so report
			# what went wrong and terminate.
			systemctl status cachefilesd
			exit 1
		fi
	fi

	echo "FS-Cache started"
}

# create_fs_cache() creates a filesystem on the
# local NVMe instance store and mounts it to /var/cache/fscache
function create_fs_cache() {
	local mount_point=/var/cache/fscache

	mkdir -p "${mount_point}"

	dev=$(lsblk -pno NAME,TYPE,MODEL \
		| grep 'disk' \
		| grep 'NVMe Instance Storage' \
		| awk '{print $1}' \
		| sort -V \
		| tr '\n' ' ' \
		| sed 's/[[:space:]]*$//')

	if ! has_fs $dev; then
		echo "Creating filesystem on ${dev}..."
		# nosemgrep: unquoted-variable-expansion-in-command
		mkfs.ext4 -m 0 -F -E lazy_itable_init=1,lazy_journal_init=1,nodiscard -O sparse_super ${dev}
		echo "Finished formatting ${dev}"
	else
		echo "Filesystem already present on ${dev}; skipping mkfs"
	fi

	echo "Mounting ${dev} to FS-Cache directory (${mount_point})..."
	# nosemgrep: unquoted-variable-expansion-in-command
	mount -o discard,defaults,nobarrier,init_itable=0 ${dev} "${mount_point}"
	echo "Finished mounting ${dev} to FS-Cache directory (${mount_point})"

	start_fs_cache
}

# mount_nfs_server() mounts the NFS server
function mount_nfs_server() {
	local remote="${NFS_SERVER}:/data"
	local path="/srv/nfs/data"

	# Make the local export directory
	mkdir -p "$path"

	# In the main terraform script this only attempts 3 times, 60 seconds apart.
	# For the demo, keep trying 15 seconds apart to get faster feedback.
	# The demo is expected to be interactive so this will allow the user time
	# to diagnose and fix the issue.
	local -i attempt=1
	while true; do
		echo "(Attempt ${attempt}) Mounting NFS Share: ${remote}..."
		if mount -t nfs -o "${MOUNT_OPTIONS}" "${remote}" "${path}"; then
			echo "NFS mount succeeded for ${remote}."
			break
		else
			echo "NFS mount failed for ${remote}. Retrying after 15 seconds..."
			((attempt++))
			sleep 15
		fi
	done
}

# export_nfs_share() exports the NFS share
function export_nfs_share() {
	echo "Creating NFS share export."
	echo "/srv/nfs/data   *(rw,wdelay,no_root_squash,no_subtree_check,fsid=10,sec=sys,rw,secure,no_root_squash,no_all_squash)" > /etc/exports
	exportfs -a
}

# start_nfs() starts the NFS server
function start_nfs() {
	# Start NFS Server
	echo "Starting nfs-kernel-server..."
	systemctl daemon-reload
	if ! systemctl start portmap nfs-kernel-server; then
		systemctl status portmap nfs-kernel-server
		exit 1
	fi
	echo "Finished starting nfs-kernel-server..."

	echo "### NFS Mount ###"
	findmnt -ut nfs,nfs4

	echo "### NFS Export ###"
	exportfs -s
}

create_fs_cache
mount_nfs_server
export_nfs_share
start_nfs
