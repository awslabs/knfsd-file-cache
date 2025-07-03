#!/bin/bash

# Copyright 2020 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Exit immediately if a command exits with a non-zero status
set -o errexit
set -o pipefail
shopt -s lastpipe

declare -A PARAMETERS

SHELL_YELLOW='\033[0;33m'
SHELL_DEFAULT='\033[0m'

# get metadata from IMDSv2
function get_metadata() {
	local token
	token=$(curl -s --retry 5 --retry-max-time 30 -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 3600" "http://169.254.169.254/latest/api/token")
	REGION=$(curl -s --retry 5 --retry-max-time 30 -H "X-aws-ec2-metadata-token:${token}" "http://169.254.169.254/latest/meta-data/placement/region")
	INSTANCE_ID=$(curl -s --retry 5 --retry-max-time 30 -H "X-aws-ec2-metadata-token:${token}" "http://169.254.169.254/latest/meta-data/instance-id")
}

# update_status() updates the tag:"knfsd-file-cache:status" of the instance
# @param (str) $1 message
function update_status() {
	aws ec2 create-tags \
		--region "${REGION}" \
		--resources "${INSTANCE_ID}" \
		--tags "Key=knfsd-file-cache:status,Value=$1"
}

# format the terminal for a command output
function begin_command() {
	echo -e "${SHELL_YELLOW}---- RUNNING: $1${SHELL_DEFAULT}"
	update_status "running: $1"
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

# load_parameters() retrieves all parameters from SSM Parameter Store
function load_parameters() {
	local PARAM_PATH="/knfsd/${CLUSTER_NAME}"
	echo "Loading parameters from ${PARAM_PATH}"

	local PARAMS_JSON
	PARAMS_JSON=$(aws ssm get-parameters-by-path \
		--region "${REGION}" \
		--path "${PARAM_PATH}" \
		--recursive \
		--with-decryption)

	# Check if parameters were retrieved successfully
	if [[ -z ${PARAMS_JSON} ]]; then
		echo "ERROR: Failed to retrieve parameters from ${PARAM_PATH}" >&2
		exit 1
	fi

	# Extract parameters from the JSON output and store in associative array
	echo "${PARAMS_JSON}" | jq -r '.Parameters[] | [.Name, (.Value | @base64)] | @tsv' | while IFS=$'\t' read -r path encoded_value; do
		local param_name value
		param_name=$(basename "${path}")
		value=$(echo "${encoded_value}" | base64 -d)
		# convert SSM Parameter Store value="" to actual empty string
		if [[ ${value} == '""' ]]; then
			value=""
		fi
		PARAMETERS[${param_name}]=${value}
	done

	echo "Successfully loaded ${#PARAMETERS[@]} parameters"

	echo "PARAMETERS:"
	printf '%s\n' "${!PARAMETERS[@]}" | sort | while read -r param_name; do
		value="${PARAMETERS[${param_name}]}"
		if [[ $value == *$'\n'* ]]; then
			echo "  ${param_name} ="
			echo "$value" | sed 's/^/    /'
		else
			echo "  ${param_name} = $value"
		fi
	done
}

# get_parameter() retrieves a parameter from the PARAMETERS array
# @param (str) parameter name
function get_parameter() {
	echo "${PARAMETERS[$1]}"
}

# build_mount_options() builds the mount options from the SSM Parameter Store parameters
# Do not use this directly when mounting NFS exports, instead use the MOUNT_OPTIONS
# variable. This is because other actions by the script can append additional options
# such as 'fsc'.
function build_mount_options() {
	local -a OPTIONS=(
		rw noatime nocto async hard ac
		vers="$(get_parameter NFS_MOUNT_VERSION)"
		proto=tcp
		timeo=600
		retrans=2
		lookupcache=all
		local_lock=none
		nconnect="$(get_parameter NCONNECT)"
		acdirmin="$(get_parameter ACDIRMIN)"
		acdirmax="$(get_parameter ACDIRMAX)"
		acregmin="$(get_parameter ACREGMIN)"
		acregmax="$(get_parameter ACREGMAX)"
		rsize="$(get_parameter RSIZE)"
		wsize="$(get_parameter WSIZE)"
	)

	# NFSv4 does not use mountproto, only add this option if using NFSv3
	if [[ "$(get_parameter NFS_MOUNT_VERSION)" == "3" ]]; then
		OPTIONS+=("mountproto=tcp")
	fi

	local EXTRA_OPTIONS
	EXTRA_OPTIONS="$(get_parameter MOUNT_OPTIONS)"
	if [[ -n ${EXTRA_OPTIONS} ]]; then
		OPTIONS+=("${EXTRA_OPTIONS}")
	fi

	printf -v joined '%s,' "${OPTIONS[@]}"
	echo "${joined%,}"
}

# build_export_options() builds the common export options for all exports
# Do not use this directly, the result will be cached in EXPORT_OPTIONS
function build_export_options() {
	local NOHIDE EXTRA_OPTIONS
	NOHIDE="$(get_parameter NOHIDE)"
	EXTRA_OPTIONS="$(get_parameter EXPORT_OPTIONS)"

	local -a OPTIONS=(
		rw
		sync
		wdelay
		no_root_squash
		no_all_squash
		no_subtree_check
		sec=sys
		secure
	)

	if [[ ${AUTO_REEXPORT} == 'true' ]]; then
		# AUTO_REEXPORT overrides nohide with the crossmnt option
		OPTIONS+=(crossmnt)
	elif [[ ${NOHIDE} == 'true' ]]; then
		OPTIONS+=(nohide)
	fi

	if [[ -n ${EXTRA_OPTIONS} ]]; then
		OPTIONS+=("${EXTRA_OPTIONS}")
	fi

	printf -v joined '%s,' "${OPTIONS[@]}"
	echo "${joined%,}"
}

# mount_nfs_server() mounts an NFS Server from the cache
# @param (str) $1 NFS Sever IP
# @param (str) $2 NFS Server Export Path
# @param (str) $3 Local Mount Path
# @param (str) $4 FS Type <optional>
function mount_nfs_server() {
	if [[ -L $3 ]]; then
		# terminate so that the proxy does not start with a bad configuration
		echo "ERROR: Cannot mount $1:$2 because $3 matches a symlink" >&2
		exit 1
	fi

	local remote="$1:$2"
	local path="/srv/nfs/$3"
	local fstype="${4:-nfs}"
	local FSTYPE="${fstype^^}"

	# make the local export directory
	mkdir -p "$path"

	# remove nconnect option if fstype=efs
	local mount_opts="$MOUNT_OPTIONS"
	if [[ $fstype == "efs" ]]; then
		mount_opts="$(echo "$mount_opts" | sed -E 's/(^|,)(nconnect=[^,]*,?)/\1/g; s/,,+/,/g; s/^,+//; s/,+$//')"
		echo "Removed [nconnect] option from MOUNT_OPTIONS: $mount_opts"
	fi

	if [[ $fstype == "efs" ]]; then
		# EFS mount helper has its own retry logic, so attempt only once
		echo "Mounting $FSTYPE share: $remote..."
		if mount -t "$fstype" -o "$mount_opts" "$remote" "$path"; then
			echo "$FSTYPE mount succeeded for $remote"
		else
			echo "ERROR: $FSTYPE mount failed for $remote" >&2
			exit 1
		fi
	else
		# try to mount the NFS share 3 times, 30 seconds apart
		local -i attempt
		for ((attempt = 1; ; attempt++)); do
			echo "(Attempt ${attempt}/3) Mounting $FSTYPE share: $remote..."
			if mount -t "$fstype" -o "$mount_opts" "$remote" "$path"; then
				echo "$FSTYPE mount succeeded for $remote"
				break
			else
				if ((attempt >= 3)); then
					echo "ERROR: $FSTYPE mount failed for $remote. Maximum attempts reached, exiting with status 1..." >&2
					exit 1
				fi
				echo "$FSTYPE mount failed for $remote. Retrying after 30 seconds..."
				sleep 30
			fi
		done
	fi
}

# add_nfs_export() adds an entry to /etc/exports
# @param (str) Local Directory
NEXT_FSID=1
function add_nfs_export() {
	local FSID

	if [[ ${FSID_MODE} == "static" ]]; then
		# Statically assign fsid numbers to exports without using the fsidd service.
		# This doesn't really have any advantage over FSID_MODE=local, but can be
		# useful for testing, debugging or troubleshooting.
		if [[ $1 == / ]]; then
			# Special handling when re-exporting root exports.
			# For NFS v4 the FSID of the root should be set to 0.
			FSID="fsid=0"
		else
			FSID="fsid=${NEXT_FSID}"
			NEXT_FSID=$((NEXT_FSID + 1))
		fi
	else
		# For FSID_MODE local or external use reexport=auto-fsidnum to automatically
		# assign fsid numbers using the fsidd service.
		# When FSID_MODE is set to external this will ensure that all the knfsd
		# instances in a cluster have the same fsid for each export.
		# This is less useful when FSID_MODE is set to local, but it will still
		# ensure the knfsd instance uses the same fsids after a reboot.

		if [[ $1 == / ]]; then
			# Special handling when re-exporting root exports.
			# For NFS v4 the FSID of the root should be set to 0.
			FSID="fsid=0,reexport=auto-fsidnum"
		else
			FSID="reexport=auto-fsidnum"
		fi
	fi

	echo "Creating NFS share export for $1..."
	echo "$1   ${EXPORT_CIDR}(${EXPORT_OPTIONS},${FSID})" >> /etc/exports
	echo "Finished creating NFS share export for $1"
}

# rexport() mounts and reexports an NFS share from another NFS server
# @param (str) $1 NFS Server IP
# @param (str) $2 NFS Server Export Path
# @param (str) $3 Local Mount Path
# @param (str) $4 FS Type <optional>
function reexport() {
	mount_nfs_server "$1" "$2" "$3" "$4"
	add_nfs_export "$3"
}

# filter_exports() filters exports based on the include and exclude patterns.
# Reads list of exports from stdin and writes the filtered list to stdout.
# Any parameters are passed to the filter-exports command
function filter_exports() {
	filter-exports "$@" \
		-include "${WORKDIR}/include-filters" \
		-exclude "${WORKDIR}/exclude-filters" \
		-verbose
}

# split() splits a list of comma delimited values
# Leading and trailing whitespace is trimmed, empty values are ignored.
# The results are output one item per line.
function split() {
	tr ',' '\n' | sed 's/^\s*//; s/\s*$//' | sed '/^$/d'
}

# trim_slash() removes any trailing slashes from paths
# For example /local/bin/ will be changed to /local/bin.
# A special case is made for / which will be left unchanged.
function trim_slash() {
	sed '\|^/$| !s|/*$||'
}

# stop_services() stops one or more services using systemctl.
# If there is an error stopping the services systemctl is used to check the
# status and view the most recent log entries.
function stop_services() {
	if ! systemctl stop "$@"; then
		systemctl status "$@"
		exit 1
	fi
}

# disable_services() disables one or more services using systemctl.
# If there is an error disabling the services systemctl is used to check the
# status and view the most recent log entries.
function disable_services() {
	if ! systemctl disable "$@"; then
		systemctl status "$@"
		exit 1
	fi
}

# helper function to stop and disable one or more services
function stop_and_disable_services() {
	stop_services "$@"
	disable_services "$@"
}

# start_services() starts one or more services using systemctl.
# If there is an error starting the services systemctl is used to check the
# status and view the most recent log entries.
function start_services() {
	if ! systemctl start "$@"; then
		systemctl status "$@"
		exit 1
	fi
}

function init() {
	get_metadata
	begin_command "initialize"
	# Set any variables cleanup depends upon as blank before setting the trap.
	# This prevents stray environment variables causing unexpected behaviour.
	startup_complete=
	WORKDIR=
	trap cleanup EXIT

	# load parameters
	load_parameters

	# reload systemd daemon to pick up any service file changes from image build
	echo "Reloading systemd daemon..."
	systemctl daemon-reload

	WORKDIR="$(mktemp -d)"
	# get_parameter INCLUDED_EXPORTS | split >"${WORKDIR}/include-filters"
	# get_parameter EXCLUDED_EXPORTS | split >"${WORKDIR}/exclude-filters"
	get_parameter INCLUDED_EXPORTS > "${WORKDIR}/include-filters"
	get_parameter EXCLUDED_EXPORTS > "${WORKDIR}/exclude-filters"

	EXPORT_MAP=$(get_parameter EXPORT_MAP)
	EXPORT_HOST_AUTO_DETECT=$(get_parameter EXPORT_HOST_AUTO_DETECT)
	EXPORT_CIDR=$(get_parameter EXPORT_CIDR)

	AUTO_REEXPORT="$(get_parameter AUTO_REEXPORT)"
	FSID_MODE="$(get_parameter FSID_MODE)"
	get_parameter FSID_DATABASE_CONFIG > /etc/knfsd-fsidd.conf

	MOUNT_OPTIONS="$(build_mount_options)"
	EXPORT_OPTIONS="$(build_export_options)"

	NUM_NFS_THREADS=$(get_parameter NUM_NFS_THREADS)
	VFS_CACHE_PRESSURE=$(get_parameter VFS_CACHE_PRESSURE)
	DISABLED_NFS_VERSIONS=$(get_parameter DISABLED_NFS_VERSIONS)
	READ_AHEAD=$(get_parameter READ_AHEAD)

	CACHEFILESD_DISK_TYPE=$(get_parameter CACHEFILESD_DISK_TYPE)

	ENABLE_METRICS=$(get_parameter ENABLE_METRICS)
	METRICS_AGENT_CONFIG=$(get_parameter METRICS_AGENT_CONFIG)
	ENABLE_KNFSD_AGENT=$(get_parameter ENABLE_KNFSD_AGENT)

	# Auto-discovery of exports using NetApp API.
	# Need to be exported so that the netapp-exports tool can read them from
	# the local environment.
	ENABLE_NETAPP_AUTO_DETECT="$(get_parameter ENABLE_NETAPP_AUTO_DETECT)"
	export ENABLE_NETAPP_AUTO_DETECT

	NETAPP_HOST="$(get_parameter NETAPP_HOST)"
	export NETAPP_HOST

	NETAPP_URL="$(get_parameter NETAPP_URL)"
	export NETAPP_URL

	NETAPP_USER="$(get_parameter NETAPP_USER)"
	export NETAPP_USER

	NETAPP_SECRET="$(get_parameter NETAPP_SECRET)"
	export NETAPP_SECRET

	NETAPP_SECRET_REGION="$(get_parameter NETAPP_SECRET_REGION)"
	export NETAPP_SECRET_REGION

	NETAPP_SECRET_VERSION="$(get_parameter NETAPP_SECRET_VERSION)"
	export NETAPP_SECRET_VERSION

	NETAPP_CA="$(get_parameter NETAPP_CA)"
	export NETAPP_CA

	NETAPP_ALLOW_COMMON_NAME="$(get_parameter NETAPP_ALLOW_COMMON_NAME)"
	export NETAPP_ALLOW_COMMON_NAME

	# NetApp CA certificate needs to be stored in a file
	if [[ -n ${NETAPP_CA} ]]; then
		echo "${NETAPP_CA}" > "${WORKDIR}/netapp-ca.pem"
		NETAPP_CA="${WORKDIR}/netapp-ca.pem"
		export NETAPP_CA
	fi

	echo "Done setting parameters"

	# Truncate the exports file to avoid stale/duplicate exports if the server restarts
	: > /etc/exports

	# Run the CUSTOM_PRE_STARTUP_SCRIPT
	echo "Running CUSTOM_PRE_STARTUP_SCRIPT..."
	echo "${CUSTOM_PRE_STARTUP_SCRIPT}" > /custom-pre-startup-script.sh
	chmod +x /custom-pre-startup-script.sh
	bash /custom-pre-startup-script.sh
	echo "Finished running CUSTOM_PRE_STARTUP_SCRIPT..."
	complete_command
}

# create_fs_cache() creates a RAID 0 array from local NVMe
# or EBS volumes and mounts it to /var/cache/fscache
function create_fs_cache() {
	begin_command "create fs-cache"
	local DEVICESLIST NUMDEVICES

	# Check if we are setting up Local NVMe or EBS volume(s)
	if [[ ${CACHEFILESD_DISK_TYPE} == "local-nvme" ]]; then

		# Find attached NVMe instance store volumes
		echo "Detecting local NVMe devices for FS-Cache..."

		# collect nvme devices
		DEVICESLIST=$(lsblk -pno NAME,TYPE,MODEL \
			| grep 'disk' \
			| grep 'NVMe Instance Storage' \
			| awk '{print $1}' \
			| sort -V \
			| tr '\n' ' ')
		NUMDEVICES=$(echo "${DEVICESLIST}" | wc -w)
		echo "Detected ${NUMDEVICES} devices: ${DEVICESLIST}"

		# If there are local NVMe drives attached, start the process of formatting and mounting
		if [ ${NUMDEVICES} -eq 0 ]; then
			echo "ERROR: No NVMe devices found"
			exit 1
		elif [ ${NUMDEVICES} -eq 1 ]; then
			echo "Formatting single NVMe device..."
			# nosemgrep: unquoted-variable-expansion-in-command
			mkfs.ext4 -m 0 -F -E lazy_itable_init=1,lazy_journal_init=1,nodiscard -O sparse_super ${DEVICESLIST}
			echo "Finished formatting NVMe device"

			# Mount NVMe device to /var/cache/fscache & start FS-Cache
			# nosemgrep: unquoted-variable-expansion-in-command
			mount -o discard,defaults,nobarrier,init_itable=0 ${DEVICESLIST} /var/cache/fscache
			echo "Finished mounting NVMe device to FS-Cache directory (/var/cache/fscache)"
			start_fs_cache
		else
			# Create RAID 0 array from multiple NVMe devices
			if [ ! -e /dev/md127 ]; then
				echo "Creating RAID 0 array from ${NUMDEVICES} NVMe devices..."
				# nosemgrep: unquoted-variable-expansion-in-command
				mdadm --create /dev/md127 --level=0 --force --quiet --assume-clean --raid-devices=${NUMDEVICES} ${DEVICESLIST}
				echo "Finished creating RAID 0 array from ${NUMDEVICES} NVMe devices"
			fi

			# Check if the RAID 0 array has already been formatted
			echo "Checking if RAID 0 array needs formatting..."
			is_formatted=$(fsck -N /dev/md127 | grep ext4 || true)
			if [[ $is_formatted == "" ]]; then
				echo "RAID 0 array is not formatted. Formatting..."
				mkfs.ext4 -m 0 -F -E lazy_itable_init=1,lazy_journal_init=1,nodiscard -O sparse_super /dev/md127
				echo "Finished formatting RAID 0 array"
			else
				echo "RAID 0 array is already formatted"
			fi

			# Mount /dev/md127 to /var/cache/fscache & start FS-Cache
			mount -o discard,defaults,nobarrier,init_itable=0 /dev/md127 /var/cache/fscache
			echo "Finished mounting /dev/md127 to FS-Cache directory (/var/cache/fscache)"
			start_fs_cache
		fi
	else
		# Find attached EBS volumes
		echo "Detecting EBS volumes for FS-Cache..."

		# collect ebs volumes except the root device
		root_device=$(lsblk -pno PKNAME "$(findmnt -n -o SOURCE /)")
		DEVICESLIST=$(lsblk -pno NAME,TYPE,MODEL \
			| grep 'disk' \
			| grep -v 'NVMe Instance Storage' \
			| awk '{print $1}' \
			| grep -v "^$root_device$" \
			| sort -V \
			| tr '\n' ' ')
		NUMDEVICES=$(echo "${DEVICESLIST}" | wc -w)
		echo "Detected ${NUMDEVICES} devices: ${DEVICESLIST}"

		# If there are EBS volumes attached, start the process of formatting and mounting
		if [ ${NUMDEVICES} -eq 0 ]; then
			echo "ERROR: No EBS volumes found"
			exit 1
		elif [ ${NUMDEVICES} -eq 1 ]; then
			echo "Formatting single EBS volume..."
			# nosemgrep: unquoted-variable-expansion-in-command
			mkfs.ext4 -m 0 -E lazy_itable_init=1,lazy_journal_init=1,nodiscard -O sparse_super ${DEVICESLIST}
			echo "Finished formatting EBS volume"

			# Mount EBS volume to /var/cache/fscache & start FS-Cache
			# nosemgrep: unquoted-variable-expansion-in-command
			mount -o discard,defaults,nobarrier,init_itable=0 ${DEVICESLIST} /var/cache/fscache
			echo "Finished mounting EBS volume to FS-Cache directory (/var/cache/fscache)"
			start_fs_cache
		else
			# Create RAID 0 array from multiple EBS volumes
			if [ ! -e /dev/md127 ]; then
				echo "Creating RAID 0 array from ${NUMDEVICES} EBS volumes..."
				# nosemgrep: unquoted-variable-expansion-in-command
				mdadm --create /dev/md127 --level=0 --force --quiet --assume-clean --raid-devices=${NUMDEVICES} ${DEVICESLIST}
				echo "Finished creating RAID 0 array from ${NUMDEVICES} EBS volumes"
			fi

			# Check if the RAID 0 array has already been formatted
			echo "Checking if RAID 0 array needs formatting..."
			is_formatted=$(fsck -N /dev/md127 | grep ext4 || true)
			if [[ $is_formatted == "" ]]; then
				echo "RAID 0 array is not formatted. Formatting..."
				mkfs.ext4 -m 0 -F -E lazy_itable_init=1,lazy_journal_init=1,nodiscard -O sparse_super /dev/md127
				echo "Finished formatting RAID 0 array"
			else
				echo "RAID 0 array is already formatted"
			fi

			# Mount /dev/md127 to /var/cache/fscache & start FS-Cache
			mount -o discard,defaults,nobarrier,init_itable=0 /dev/md127 /var/cache/fscache
			echo "Finished mounting /dev/md127 to FS-Cache directory (/var/cache/fscache)"
			start_fs_cache
		fi
	fi
	complete_command
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

	MOUNT_OPTIONS="${MOUNT_OPTIONS},fsc"
	echo "FS-Cache started"
}

# start_fsidd() starts the correct FSID service based on the FSID_MODE
function start_fsidd() {
	begin_command "start fsidd"
	case "${FSID_MODE}" in
		static)
			echo "Skipping fsidd service"
			stop_and_disable_services fsidd.service knfsd-fsidd.socket knfsd-fsidd.service
			;;
		local)
			echo "Starting fsidd..."
			stop_and_disable_services knfsd-fsidd.socket knfsd-fsidd.service
			start_services fsidd.service
			echo "Finished starting fsidd"
			;;
		external)
			echo "Starting knfsd-fsidd..."
			stop_and_disable_services fsidd.service
			start_services knfsd-fsidd.socket knfsd-fsidd.service
			echo "Finished starting knfsd-fsidd"
			;;
		*)
			echo "ERROR: Unknown FSID_MODE \"${FSID_MODE}\"" >&2
			exit 1
			;;
	esac
	complete_command
}

# export_map() loops through statically defined NFS exports in $EXPORT_MAP,
# and re-exports (fn: reexport), without filtering the exports
function export_map() {
	begin_command "export map"
	if [[ -n ${EXPORT_MAP} ]]; then
		echo "Beginning processing of standard NFS re-exports (EXPORT_MAP)..."
		local i REMOTE_IP REMOTE_EXPORT LOCAL_EXPORT FSTYPE

		for i in $(echo "${EXPORT_MAP}" | sed "s/,/ /g"); do
			# Split the components of the entry in EXPORT_MAP
			REMOTE_IP="$(echo "$i" | cut -d';' -f1)"
			REMOTE_EXPORT="$(echo "$i" | cut -d';' -f2)"
			LOCAL_EXPORT="$(echo "$i" | cut -d';' -f3)"
			FSTYPE="$(echo "$i" | cut -d';' -f4)"
			reexport "${REMOTE_IP}" "${REMOTE_EXPORT}" "${LOCAL_EXPORT}" "${FSTYPE}"
		done
		echo "Finished processing of standard NFS re-exports (EXPORT_MAP)"
	else
		echo "Skipping..."
	fi
	complete_command
}

# export_auto_detect() dynamically detects NFS exports via 'showmount' command,
# filters the exports (fn: filter_exports), before re-exporting (fn: reexport)
function export_auto_detect() {
	begin_command "export auto-detect"
	if [[ -n ${EXPORT_HOST_AUTO_DETECT} ]]; then
		echo "Beginning processing of dynamically detected host exports (EXPORT_HOST_AUTO_DETECT)..."
		local REMOTE_IP REMOTE_EXPORT

		for REMOTE_IP in $(echo "${EXPORT_HOST_AUTO_DETECT}" | sed "s/,/ /g"); do
			# Detect the mounts on the NFS Server
			showmount -e --no-headers "$REMOTE_IP" | filter_exports -field 1 | awk '{print $1}' | sort \
				| while read -r REMOTE_EXPORT; do
					# Mount the NFS Server export
					reexport "${REMOTE_IP}" "${REMOTE_EXPORT}" "${REMOTE_EXPORT}"
				done
		done
		echo "Finished processing of dynamically detected host exports (EXPORT_HOST_AUTO_DETECT)"
	else
		echo "Skipping..."
	fi
	complete_command
}

# export_netapp() dynamically detects NetApp specific exports via NetApp RESTful API (golang: netapp-exports),
# filters the exports (fn: filter_exports), before re-exporting (fn: reexport)
function export_netapp() {
	begin_command "export netapp"
	if [[ ${ENABLE_NETAPP_AUTO_DETECT} == "true" ]]; then
		echo "Beginning processing of dynamically detected NetApp exports (ENABLE_NETAPP_AUTO_DETECT)..."
		local REMOTE_IP REMOTE_EXPORT

		netapp-exports | filter_exports -field 2 \
			| while read -r REMOTE; do
				REMOTE_IP="$(echo "${REMOTE}" | cut -d ' ' -f1)"
				REMOTE_EXPORT="$(echo "${REMOTE}" | cut -d ' ' -f2-)"

				# Mount the NFS Server export
				reexport "${REMOTE_IP}" "${REMOTE_EXPORT}" "${REMOTE_EXPORT}"
			done
		echo "Finished processing of dynamically detected NetApp exports (ENABLE_NETAPP_AUTO_DETECT)"
	else
		echo "Skipping..."
	fi
	complete_command
}

# configure_read_ahead() sets the read ahead value for NFS mounts
function configure_read_ahead() {
	begin_command "configure read ahead"
	# Set read ahead value to 8 MiB
	# Originally read ahead default to rsize * 15, but with rsizes now allowing 1 MiB
	# a 15 MiB read ahead was too large. Newer versions of Ubuntu changed the
	# default to a fixed value of 128 KiB which is now too small.
	# Currently we're assuming the max read size of 1 MiB and using rsize * 8.
	echo "Setting read ahead for NFS mounts..."

	READ_AHEAD_KB=$((READ_AHEAD / 1024))

	findmnt -rnu -t nfs,nfs4 -o MAJ:MIN,TARGET \
		| while read -r MOUNT; do
			DEVICE="$(cut -d ' ' -f 1 <<< "${MOUNT}")"
			MOUNT_PATH="$(cut -d ' ' -f 2- <<< "${MOUNT}")"
			echo "Setting read ahead for: ${MOUNT_PATH} to: ${READ_AHEAD_KB} KiB"
			echo "${READ_AHEAD_KB}" > /sys/class/bdi/"${DEVICE}"/read_ahead_kb
		done
	echo "Finished setting read ahead for NFS mounts"
	complete_command
}

# configure_nfs() sets the VFS Cache Pressure and disables unwanted NFS Versions
function configure_nfs() {
	begin_command "configure nfs"
	# Set VFS Cache Pressure
	echo "Setting VFS Cache Pressure to: ${VFS_CACHE_PRESSURE}"
	sysctl vm.vfs_cache_pressure="${VFS_CACHE_PRESSURE}"

	# Build Flags to Disable NFS Versions
	DISABLED_NFS_VERSIONS_FLAGS=("vers2=no")
	for v in $(echo "${DISABLED_NFS_VERSIONS}" | sed "s/,/ /g"); do
		DISABLED_NFS_VERSIONS_FLAGS+=("vers$v=no")
	done
	DISABLED_NFS_VERSIONS_CONFIG=$(printf '%s\n' "${DISABLED_NFS_VERSIONS_FLAGS[@]}")

	# Set NFS Kernel Server Config
	echo "Setting number of NFS Threads to: ${NUM_NFS_THREADS}"
	cat <<- EOF > /etc/nfs.conf.d/knfsd.conf
		[nfsd]
		threads=${NUM_NFS_THREADS}
		${DISABLED_NFS_VERSIONS_CONFIG}
	EOF
	complete_command
}

# configure_metrics() enables the Metrics Agent & CloudWatch Agent
function configure_metrics() {
	begin_command "configure metrics"
	local cw_pid kma_pid
	# enable metrics if configured
	if [[ ${ENABLE_METRICS} == "true" ]]; then
		echo "Starting Metrics Agents..."
		printf '%s' "${METRICS_AGENT_CONFIG}" > /etc/knfsd-metrics-agent/custom.yaml
		amazon-cloudwatch-agent-ctl -m ec2 -a fetch-config -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s &
		cw_pid=$!
		start_services knfsd-metrics-agent &
		kma_pid=$!
		wait ${cw_pid} ${kma_pid}
		echo "Finished starting Metrics Agents"
	else
		echo "Metrics are disabled. Skipping..."
	fi
	complete_command
}

# start_nfs() starts the KNFSD-Agent if enabled & NFS Server
function start_nfs() {
	begin_command "start nfs"
	# enable knfsd agent if configured
	if [[ ${ENABLE_KNFSD_AGENT} == "true" ]]; then
		echo "Starting KNFSD Agent..."
		start_services knfsd-agent
		echo "Finished starting KNFSD Agent"
	else
		echo "KNFSD Agent disabled. Skipping..."
	fi

	# Start NFS Server
	echo "Starting nfs-kernel-server..."
	start_services portmap nfs-kernel-server
	echo "Finished starting nfs-kernel-server..."
	complete_command
}

# post_startup() runs the CUSTOM_POST_STARTUP_SCRIPT
function post_startup() {
	begin_command "post startup"
	# Run the CUSTOM_POST_STARTUP_SCRIPT
	echo "Running CUSTOM_POST_STARTUP_SCRIPT..."
	echo "${CUSTOM_POST_STARTUP_SCRIPT}" > /custom-post-startup-script.sh
	chmod +x /custom-post-startup-script.sh
	bash /custom-post-startup-script.sh
	echo "Finished running CUSTOM_POST_STARTUP_SCRIPT..."

	echo -e "${SHELL_YELLOW}### NFS Mounts ###${SHELL_DEFAULT}"
	findmnt -ut nfs,nfs4

	echo -e "${SHELL_YELLOW}### NFS Exports ###${SHELL_DEFAULT}"
	exportfs -s

	complete_command
	echo "INFO: Reached Proxy Startup Exit. Happy caching!"
	update_status "ready"
	startup_complete=yes
}

# Do not call cleanup explicitly, the init function sets an exit trap
function cleanup() {
	# If the script exits unexpectedly print an error message. This makes it
	# easier when searching the logs to know if the start up script has
	# terminated.
	if [[ $startup_complete != yes ]]; then
		echo "ERROR: Failed to start proxy" >&2
		update_status "error: failed to start proxy"
	fi

	if [[ -n ${WORKDIR} ]] && [[ -d ${WORKDIR} ]]; then
		rm -rf "${WORKDIR}" || true
	fi
}

# main() is the main function that is called when the script is executed
function main() {
	init
	create_fs_cache

	echo "MOUNT_OPTIONS: ${MOUNT_OPTIONS}"
	echo "EXPORT_OPTIONS: ${EXPORT_OPTIONS}"

	export_map
	export_auto_detect
	export_netapp

	configure_read_ahead
	configure_nfs
	configure_metrics

	start_fsidd
	start_nfs
	post_startup
}

# Do not execute the main() function if this script has been loaded for
# unit testing ($BATS_VERSION is only present if bats is running)
if [[ -z ${BATS_VERSION} ]]; then
	main
fi
