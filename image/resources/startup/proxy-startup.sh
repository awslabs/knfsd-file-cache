#!/usr/bin/env bash

# Copyright 2020 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# exit immediately if a command exits with a non-zero status
set -o errexit
set -o pipefail
shopt -s lastpipe

declare -A PARAMETERS

SHELL_RED='\033[0;31m'
SHELL_YELLOW='\033[0;33m'
SHELL_DEFAULT='\033[0m'

EXPORTS_FILE="/etc/exports.d/knfsd.exports"
STATUS_TAGS="enabled"
REGION=$(cloud-init query region)
INSTANCE_ID=$(cloud-init query instance_id)

# update_status() updates the tag:"knfsd-file-cache:status" of the instance
# @param (str) $1 message
function update_status() {
	[[ ${STATUS_TAGS} == "enabled" ]] || return 0
	if ! aws ec2 create-tags \
		--region "${REGION}" \
		--resources "${INSTANCE_ID}" \
		--tags "Key=knfsd-file-cache:status,Value=$1" \
		--cli-connect-timeout 5 \
		--cli-read-timeout 10 2> /dev/null; then
		STATUS_TAGS="disabled"
		echo "WARNING: unable to set tag \"knfsd-file-cache:status\", disabling status tagging for this boot" >&2
		echo "WARNING: check the EC2 API is reachable (add a \"com.amazonaws.${REGION}.ec2\" interface VPC endpoint, a NAT gateway, or a public IP) and that the instance role grants \"ec2:CreateTags\"" >&2
		echo "WARNING: startup continues and NFS caching is unaffected, but Terraform \"ENABLE_STATUS_CHECK\" and the AWS Console status column will not work" >&2
	fi
	return 0
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
	if ! PARAMS_JSON=$(aws ssm get-parameters-by-path \
		--region "${REGION}" \
		--path "${PARAM_PATH}" \
		--recursive \
		--with-decryption \
		--cli-connect-timeout 5 \
		--cli-read-timeout 30); then
		echo "ERROR: failed to read parameters from SSM Parameter Store path ${PARAM_PATH}" >&2
		echo "ERROR: check the SSM API is reachable (add a \"com.amazonaws.${REGION}.ssm\" interface VPC endpoint, a NAT gateway, or a public IP) and that the instance role grants \"ssm:GetParametersByPath\" for \"${PARAM_PATH}\"" >&2
		exit 1
	fi

	# extract parameters from the JSON output and store in associative array
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

	if [[ ${#PARAMETERS[@]} -eq 0 ]]; then
		echo "ERROR: no parameters found under ${PARAM_PATH}" >&2
		echo "ERROR: check \"CLUSTER_NAME\" matches the deployed cluster and the instance role grants \"ssm:GetParametersByPath\" for that path" >&2
		exit 1
	fi

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
function mount_nfs_server() {
	if [[ -L $3 ]]; then
		echo "ERROR: Cannot mount $1:$2 because $3 matches a symlink" >&2
		return 1
	fi

	local remote="$1:$2"
	local path="/srv/nfs/$3"

	# skip if local $path is already mounted
	if is_mounted "$path"; then
		echo "Skipping NFS path, already mounted: $path"
		return
	fi

	# make the local export directory
	mkdir -p "$path"

	# try to mount the NFS share 3 times, 30 seconds apart
	local -i attempt
	for ((attempt = 1; ; attempt++)); do
		echo "(Attempt ${attempt}/3) Mounting NFS share: $remote..."
		if mount -t nfs -o "$MOUNT_OPTIONS" "$remote" "$path"; then
			echo "NFS mount succeeded for $remote"
			break
		else
			if ((attempt >= 3)); then
				echo "ERROR: NFS mount failed for $remote. Maximum attempts reached..." >&2
				return 1
			fi
			echo "NFS mount failed for $remote. Retrying after 30 seconds..."
			sleep 30
		fi
	done
}

# add_nfs_export() adds an entry to /etc/exports.d/knfsd.exports
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

	# write one export line per CIDR
	while IFS= read -r cidr; do
		[[ -n "$cidr" ]] && echo "$1   ${cidr}(${EXPORT_OPTIONS},${FSID})" >> "${EXPORTS_FILE}"
	done <<< "$EXPORT_CIDR"

	echo "Finished creating NFS share export for $1"
}

# has_fs() checks if a path has a filesystem
# @param (str) $1 Path
# @return (bool)
function has_fs() {
	lsblk -no FSTYPE "$1" | grep -q .
}

# is_mounted() checks if a path is mounted
# @param (str) $1 Path
# @return (bool)
function is_mounted() {
	findmnt -rn "$1" > /dev/null 2>&1
}

# rexport() mounts and reexports an NFS share from another NFS server
# @param (str) $1 NFS Server IP
# @param (str) $2 NFS Server Export Path
# @param (str) $3 Local Mount Path
# @param (str) $4 FS Type <optional>
function reexport() {
	mount_nfs_server "$1" "$2" "$3" "$4" || return 1
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

# stop_services_silently() stops one or more services using systemctl.
# Any errors are ignored.
function stop_services_silently() {
	systemctl stop "$@" 2> /dev/null || true
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
	# Set any variables cleanup depends upon as blank before setting the trap.
	# This prevents stray environment variables causing unexpected behaviour.
	startup_complete=
	WORKDIR=
	trap cleanup EXIT

	begin_command "initialize"
	load_parameters

	# reload systemd daemon to pick up any service file changes from image build
	echo "Reloading systemd daemon..."
	systemctl daemon-reload

	# stop services in case of a machine reboot
	echo "Stopping services..."
	stop_services_silently cachefilesd fsidd knfsd-fsidd.socket knfsd-fsidd knfsd-agent knfsd-metrics-agent portmap nfs-kernel-server

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

	TCP_SLOT_TABLE_ENTRIES=$(get_parameter TCP_SLOT_TABLE_ENTRIES)
	TCP_MAX_SLOT_TABLE_ENTRIES=$(get_parameter TCP_MAX_SLOT_TABLE_ENTRIES)
	SVC_RPC_PER_CONNECTION_LIMIT=$(get_parameter SVC_RPC_PER_CONNECTION_LIMIT)

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

	# avoid using /etc/exports directly to avoid potential conflicts with other NFS exports
	# truncate the "knfsd.exports" file to avoid stale/duplicate exports if the server restarts
	mkdir -p /etc/exports.d
	: > ${EXPORTS_FILE}

	complete_command
}

# pre_startup() runs the CUSTOM_PRE_STARTUP_SCRIPT
function pre_startup() {
	begin_command "pre startup"
	if [[ -z "${CUSTOM_PRE_STARTUP_SCRIPT:-}" ]]; then
		echo "CUSTOM_PRE_STARTUP_SCRIPT is empty; skipping"
	else
		echo "Running CUSTOM_PRE_STARTUP_SCRIPT..."
		echo "${CUSTOM_PRE_STARTUP_SCRIPT}" | base64 -d | gzip -d > /custom-pre-startup-script.sh
		chmod +x /custom-pre-startup-script.sh
		bash /custom-pre-startup-script.sh
		echo "Finished running CUSTOM_PRE_STARTUP_SCRIPT..."
	fi
	complete_command
}

# tune_block_devices() optimises NVMe block device settings for FS-Cache workload
function tune_block_devices() {
	local devices="$1"
	local raid_dev="${2:-}"

	for dev_path in ${devices}; do
		local dev
		dev=$(basename "${dev_path}")
		echo "Tuning block device: ${dev}"
		echo 2 > /sys/block/${dev}/queue/nomerges 2> /dev/null || true
		echo 2048 > /sys/block/${dev}/queue/read_ahead_kb 2> /dev/null || true
	done

	# apply same settings to RAID device if it exists
	if [[ -n "${raid_dev}" ]] && [[ -e "${raid_dev}" ]]; then
		local md_dev
		md_dev=$(basename "${raid_dev}")
		echo "Tuning RAID device: ${md_dev}"
		echo 2 > /sys/block/${md_dev}/queue/nomerges 2> /dev/null || true
		echo 2048 > /sys/block/${md_dev}/queue/read_ahead_kb 2> /dev/null || true
	fi
}

# calculate_min_free_kbytes() computes vm.min_free_kbytes as 1% of total RAM,
# rounded to the nearest GB, with a floor of 1 GB and ceiling of 4 GB.
# Returns the value in KB via stdout.
function calculate_min_free_kbytes() {
	local total_mb
	total_mb=$(free -m | awk '/^Mem:/ {print $2}')

	# 1% of total RAM in MB
	local one_pct_mb=$((total_mb / 100))

	# round to nearest GB (1024 MB): add 512 MB then integer-divide by 1024, multiply back
	local rounded_gb=$(((one_pct_mb + 512) / 1024))

	# floor: 1 GB
	if ((rounded_gb < 1)); then
		rounded_gb=1
	fi

	# ceiling: 4 GB
	if ((rounded_gb > 4)); then
		rounded_gb=4
	fi

	# convert GB to KB
	echo $((rounded_gb * 1024 * 1024))
}

# configure_kernel() configures custom kernel settings
function configure_kernel() {
	begin_command "configure kernel"

	# Set the initial number of SUNRPC slot table entries for outbound TCP connections
	# to the source NFS filer. Each slot represents one in-flight RPC request.
	# min: 2, default: 128, max: 65536. Higher values increase parallelism to the source filer.
	sysctl -w sunrpc.tcp_slot_table_entries="${TCP_SLOT_TABLE_ENTRIES}"

	# Set the upper ceiling for SUNRPC slot table entries. The kernel can
	# dynamically grow the slot table up to this limit under load.
	# min: 2, default: 128, max: 65536
	sysctl -w sunrpc.tcp_max_slot_table_entries="${TCP_MAX_SLOT_TABLE_ENTRIES}"

	# Limit the number of SUNRPC requests the server processes in parallel from
	# a single client IP/connection. Prevents one aggressive client from
	# monopolising all nfsd threads, ensuring fair access across NFS clients.
	# min: 0 (unlimited), default: 0, max: 65536
	echo "svc_rpc_per_connection_limit = ${SVC_RPC_PER_CONNECTION_LIMIT}"
	echo ${SVC_RPC_PER_CONNECTION_LIMIT} > /sys/module/sunrpc/parameters/svc_rpc_per_connection_limit

	# Set VFS cache pressure
	# dentry/inode cache should almost never be reclaimed.
	# min: 0, default: 1, max: 100
	sysctl -w vm.vfs_cache_pressure="${VFS_CACHE_PRESSURE}"

	# Reserve ~1% of total RAM (floor 1 GB, ceiling 4 GB, rounded to nearest GB)
	# as free memory. Prevents kcompactd from urgently reclaiming NFS folios
	# under I/O pressure.
	local min_free_kb
	min_free_kb=$(calculate_min_free_kbytes)
	sysctl -w vm.min_free_kbytes=${min_free_kb}

	# Disable proactive memory compaction.
	# Proactive compaction triggers kcompactd which blocks on NFS folios
	# waiting for fscache PG_fscache flag to clear.
	# min: 0, default: 20, max: 100
	sysctl -w vm.compaction_proactiveness=0

	# Increase dirty page ceiling from 20% (default) to 40% of total memory.
	# Allows more dirty pages before the kernel forces synchronous writeback,
	# reducing write pressure spikes on the XFS log under burst cache writes.
	sysctl -w vm.dirty_ratio=40

	# Raise async writeback threshold from 10% (default) to 20% of total memory.
	# Delays background flush so dirty pages accumulate longer before pdflush
	# starts writing, reducing I/O interference during FS-Cache cold-fill bursts.
	sysctl -w vm.dirty_background_ratio=20

	# Reduce swappiness from 60 (default) to 5.
	# This is a dedicated KNFSD proxy with large amount of RAM; prefer keeping
	# NFS page cache and fscache data in memory over swapping.
	sysctl -w vm.swappiness=5

	complete_command
}

# configure_network() tunes the network stack and ENA driver
# for high-throughput NFS server/client traffic and configures ENA-X
function configure_network() {
	begin_command "configure network"

	# Raise socket buffer ceiling to 16MB so NFS can buffer 1-4MB
	# rsize/wsize responses under high concurrency.
	sysctl -w net.core.rmem_max=16777216
	sysctl -w net.core.wmem_max=16777216

	# Raise socket buffer defaults to 4MB for ENA-X high-rtt conditions
	sysctl -w net.core.rmem_default=4194304
	sysctl -w net.core.wmem_default=4194304

	# Increase network backlog from 1000 (default) to 16384 to
	# prevent packet drops at high PPS before reaching the NFS stack.
	sysctl -w net.core.netdev_max_backlog=16384

	# Set TCP auto-tuning range (min/default/max) to 4KB/128KB/16MB.
	# Aligns with rmem_max/wmem_max so TCP can auto-tune up to 16MB
	# for NFS connections with 1-100ms latency.
	sysctl -w net.ipv4.tcp_rmem="4096 131072 16777216"
	sysctl -w net.ipv4.tcp_wmem="4096 131072 16777216"

	# Raise TCP small queue limit to 4MB (default 128KB) for ENA-X
	sysctl -w net.ipv4.tcp_limit_output_bytes=4194304

	# Disable tcp_autocorking for ENA-X
	# reduces latency for request-response workloads
	echo 0 > /proc/sys/net/ipv4/tcp_autocorking

	# Set TCP congestion control algorithm to cubic for ENA-X
	sysctl -w net.ipv4.tcp_congestion_control=cubic

	# Disable TCP HyStart detection
	echo "/sys/module/tcp_cubic/parameters/hystart_detect = 0"
	echo 0 > /sys/module/tcp_cubic/parameters/hystart_detect

	# Build all-vCPU hex bitmask for RPS (Receive Packet Steering).
	# Kernel bitmap_parse expects comma-separated 32-bit hex groups
	# (MSB first), so split the mask into 32-bit chunks.
	local vcpus remaining chunk_bits chunk_val rps_mask
	vcpus=$(nproc)
	remaining=${vcpus}
	rps_mask=""
	while [[ ${remaining} -gt 0 ]]; do
		if [[ ${remaining} -ge 32 ]]; then
			chunk_bits=32
		else
			chunk_bits=${remaining}
		fi
		chunk_val=$((2 ** chunk_bits - 1))
		if [[ -z "${rps_mask}" ]]; then
			rps_mask=$(printf '%x' "${chunk_val}")
		else
			rps_mask="$(printf '%x' "${chunk_val}"),${rps_mask}"
		fi
		remaining=$((remaining - chunk_bits))
	done

	# ENA interface udev names: ens5(i3en), enp39s0(i7i), ens36(i8g), ens37(r8gd)
	for dev in /sys/class/net/en*; do
		local iface
		iface=$(basename "${dev}")

		if [[ ! -d "${dev}/device/driver/module" ]] \
			|| [[ "$(basename "$(readlink -f "${dev}/device/driver/module")")" != "ena" ]]; then
			echo "Skipping ${iface}: not an ENA device"
			continue
		fi

		echo "Tuning ENA interface: ${iface}"

		# ENA-X requires MTU 8900
		echo "${iface}: mtu = 8900"
		ip link set dev "${iface}" mtu 8900 || true

		# Increase Rx ring buffer to 8192 to absorb packet bursts
		# during FS-Cache I/O stalls. ENA-X recommended min.
		echo "${iface}: rx ring buffer = 8192"
		ethtool -G "${iface}" rx 8192 || true

		# Enable adaptive Rx interrupt moderation (DIM) to balance
		# interrupt overhead vs latency under varying load.
		echo "${iface}: adaptive-rx = on"
		ethtool -C "${iface}" adaptive-rx on || true

		# Spread softirq processing across all vCPUs via RPS
		echo "${iface}: rps_cpus = ${rps_mask}"
		for rxq in "${dev}"/queues/rx-*/rps_cpus; do
			if [[ -e "${rxq}" ]]; then
				echo "${rps_mask}" > "${rxq}" || true
			fi
		done
	done

	complete_command
}

# create_fs_cache() creates a RAID 0 array from local NVMe
# or EBS volumes and mounts it to /var/cache/fscache
function create_fs_cache() {
	begin_command "create fs-cache"
	local mount_point=/var/cache/fscache
	local root_device

	mkdir -p "${mount_point}"

	# detect device set based on cache disk type
	if [[ ${CACHEFILESD_DISK_TYPE} == "local-nvme" ]]; then
		echo "Detecting local NVMe devices for FS-Cache..."
		DEVICESLIST=$(lsblk -pno NAME,TYPE,MODEL \
			| grep 'disk' \
			| grep 'NVMe Instance Storage' \
			| awk '{print $1}' \
			| sort -V \
			| tr '\n' ' ' \
			| sed 's/[[:space:]]*$//')
	else
		echo "Detecting EBS volumes for FS-Cache..."
		root_device=$(lsblk -pno PKNAME "$(findmnt -n -o SOURCE /)")
		DEVICESLIST=$(lsblk -pno NAME,TYPE,MODEL \
			| grep 'disk' \
			| grep -v 'NVMe Instance Storage' \
			| awk '{print $1}' \
			| grep -v "^$root_device$" \
			| sort -V \
			| tr '\n' ' ' \
			| sed 's/[[:space:]]*$//')
	fi

	NUMDEVICES=$(echo "${DEVICESLIST}" | wc -w)
	echo "Detected ${NUMDEVICES} devices: ${DEVICESLIST}"

	if [ $NUMDEVICES -eq 0 ]; then
		echo "ERROR: No storage devices found" >&2
		exit 1
	elif [ $NUMDEVICES -eq 1 ]; then
		# single block device (NVMe or EBS)
		local dev
		dev=${DEVICESLIST}

		if ! has_fs $dev; then
			echo "Creating filesystem on ${dev}..."
			# -f 	force overwrite
			# -L 	set filesystem label
			# -m 	disable reflink/copy-on-write
			# nosemgrep: unquoted-variable-expansion-in-command
			mkfs.xfs -f -L fscache -m reflink=0 ${dev}
			echo "Finished formatting ${dev}"
		else
			echo "Filesystem already present on ${dev}; skipping mkfs"
		fi

		echo "Mounting ${dev} to FS-Cache directory (${mount_point})..."
		# noatime      		do not update access time on read (reduces write load)
		# lazytime     		only update times (atime, mtime, ctime) on the in-memory version of the file inode (reduces write load)
		# logbsize=256k		size of each log buffer
		# noquota      		disable quota accounting on this mount
		# nosemgrep: unquoted-variable-expansion-in-command
		mount -o noatime,lazytime,logbsize=256k,noquota ${dev} "${mount_point}"
		echo "Finished mounting ${dev} to FS-Cache directory (${mount_point})"

		tune_block_devices "${DEVICESLIST}" ""
		start_fs_cache
	else
		# multiple (NVMe or EBS) devices -> mdraid0 on /dev/md127
		local raid_dev=/dev/md127

		# always attempt to assemble RAID array from config (fail-safe)
		mdadm --assemble --scan 2> /dev/null || true

		# create RAID array if device doesn't exist
		if [[ ! -e $raid_dev ]]; then
			echo "Creating new RAID array on $raid_dev..."
			# nosemgrep: unquoted-variable-expansion-in-command
			mdadm --create $raid_dev --level=0 --force --quiet --assume-clean --raid-devices=${NUMDEVICES} ${DEVICESLIST}
			# persist RAID array configuration
			mkdir -p /etc/mdadm
			mdadm --detail --scan > /etc/mdadm/mdadm.conf
			update-initramfs -u
			echo "Finished creating RAID array"
		else
			echo "RAID array $raid_dev already exists"
		fi

		# create filesystem on RAID array if needed
		if ! has_fs $raid_dev; then
			echo "Creating filesystem on ${raid_dev}..."
			# -f 	force overwrite
			# -L 	set filesystem label
			# -d 	stripe unit 512k, stripe width = num devices (align to RAID0)
			# -l 	lazy superblock counters (less contention), log stripe unit 32k
			# -m 	disable reflink/copy-on-write
			# nosemgrep: unquoted-variable-expansion-in-command
			mkfs.xfs -f -L fscache -d su=512k,sw=${NUMDEVICES} \
				-l lazy-count=1,su=32k -m reflink=0 ${raid_dev}
			echo "Finished formatting ${raid_dev}"
		else
			echo "Filesystem already present on ${raid_dev}; skipping mkfs"
		fi

		# mount RAID array to FS-Cache directory
		echo "Mounting ${raid_dev} to FS-Cache directory (${mount_point})..."
		# noatime      		do not update access time on read (reduces write load)
		# lazytime     		only update times (atime, mtime, ctime) on the in-memory version of the file inode (reduces write load)
		# logbsize=256k		size of each log buffer
		# noquota      		disable quota accounting on this mount
		# nosemgrep: unquoted-variable-expansion-in-command
		mount -o noatime,lazytime,logbsize=256k,noquota ${raid_dev} "${mount_point}"
		echo "Finished mounting ${raid_dev} to FS-Cache directory (${mount_point})"

		tune_block_devices "${DEVICESLIST}" "${raid_dev}"
		start_fs_cache
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
			stop_and_disable_services fsidd knfsd-fsidd.socket knfsd-fsidd
			;;
		local)
			echo "Starting fsidd..."
			stop_and_disable_services knfsd-fsidd.socket knfsd-fsidd
			start_services fsidd
			echo "Finished starting fsidd"
			;;
		external)
			echo "Starting knfsd-fsidd..."
			stop_and_disable_services fsidd
			start_services knfsd-fsidd.socket knfsd-fsidd
			echo "Finished starting knfsd-fsidd"
			;;
		*)
			echo "ERROR: Unknown FSID_MODE \"${FSID_MODE}\"" >&2
			exit 1
			;;
	esac
	complete_command
}

# configure_nfs() configures the NFS kernel server and readahead settings
function configure_nfs() {
	begin_command "configure nfs"
	# build flags to disable NFS versions
	DISABLED_NFS_VERSIONS_FLAGS=("vers2=no")
	for v in $(echo "${DISABLED_NFS_VERSIONS}" | sed "s/,/ /g"); do
		DISABLED_NFS_VERSIONS_FLAGS+=("vers$v=no")
	done
	DISABLED_NFS_VERSIONS_CONFIG=$(printf '%s\n' "${DISABLED_NFS_VERSIONS_FLAGS[@]}")

	# convert readahead from bytes to KiB for nfsrahead configuration
	READ_AHEAD_KB=$((READ_AHEAD / 1024))

	echo "Setting NFS threads to: ${NUM_NFS_THREADS}"
	echo "Setting NFS readahead to: ${READ_AHEAD_KB} KiB"
	cat <<- EOF > /etc/nfs.conf.d/knfsd.conf
		[nfsd]
		threads=${NUM_NFS_THREADS}
		${DISABLED_NFS_VERSIONS_CONFIG}

		[nfsrahead]
		nfs=${READ_AHEAD_KB}
		nfs4=${READ_AHEAD_KB}
		default=${READ_AHEAD_KB}
	EOF
	complete_command
}

# export_map() loops through statically defined NFS exports in $EXPORT_MAP,
# and re-exports (fn: reexport), without filtering the exports
function export_map() {
	begin_command "export map"
	if [[ -n ${EXPORT_MAP} ]]; then
		echo "Beginning processing of NFS re-exports (EXPORT_MAP)..."
		local i REMOTE_IP REMOTE_EXPORT LOCAL_EXPORT

		for i in $(echo "${EXPORT_MAP}" | sed "s/,/ /g"); do
			# Split the components of the entry in EXPORT_MAP
			REMOTE_IP="$(echo "$i" | cut -d';' -f1)"
			REMOTE_EXPORT="$(echo "$i" | cut -d';' -f2)"
			LOCAL_EXPORT="$(echo "$i" | cut -d';' -f3)"
			reexport "${REMOTE_IP}" "${REMOTE_EXPORT}" "${LOCAL_EXPORT}"
		done
		echo "Finished processing of NFS re-exports (EXPORT_MAP)"
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
		local -a exports
		local -i mounted=0 skipped=0

		for REMOTE_IP in $(echo "${EXPORT_HOST_AUTO_DETECT}" | sed "s/,/ /g"); do
			# Detect the mounts on the NFS Server. Capture the discovered
			# exports into an array first; process substitution isolates a
			# showmount/pipe failure from errexit/pipefail and avoids relying
			# on lastpipe semantics for the counters below.
			mapfile -t exports < <(showmount -e --no-headers "$REMOTE_IP" | filter_exports -field 1 | awk '{print $1}' | sort)
			for REMOTE_EXPORT in "${exports[@]}"; do
				# Mount the NFS Server export. Unlike EXPORT_MAP, a single
				# auto-detected export that cannot be mounted (for example a
				# pseudo-root "/" advertised by some filers) is skipped rather
				# than aborting startup.
				if reexport "${REMOTE_IP}" "${REMOTE_EXPORT}" "${REMOTE_EXPORT}"; then
					mounted+=1
				else
					skipped+=1
					echo "WARNING: skipping auto-detected export ${REMOTE_IP}:${REMOTE_EXPORT}; mount failed after retries" >&2
				fi
			done
		done

		if ((mounted == 0)); then
			echo "ERROR: auto-detect (EXPORT_HOST_AUTO_DETECT) mounted zero exports; exiting" >&2
			exit 1
		fi
		echo "Finished processing of dynamically detected host exports (EXPORT_HOST_AUTO_DETECT) (mounted=${mounted}, skipped=${skipped})"
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

				# mount the NFS Server export
				reexport "${REMOTE_IP}" "${REMOTE_EXPORT}" "${REMOTE_EXPORT}"
			done
		echo "Finished processing of dynamically detected NetApp exports (ENABLE_NETAPP_AUTO_DETECT)"
	else
		echo "Skipping..."
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

	# start NFS Server
	echo "Starting nfs-kernel-server..."
	start_services portmap nfs-kernel-server
	echo "Finished starting nfs-kernel-server..."
	complete_command
}

# update_cloudwatch_diskio_resources() configures CW Agent JSON with the
# FS-Cache block devices and fscdevice dimension for RAID or single device
function update_cloudwatch_diskio_resources() {
	local cw_config="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
	local fscdevice resources

	echo "Updating CloudWatch Agent diskio configuration..."

	# convert device paths to quoted basenames, comma-separated
	resources=$(printf '%s\n' ${DEVICESLIST} | xargs -n1 basename | sed 's/.*/"&"/' | paste -sd,)

	# determine FS-Cache device and resources list
	if [[ "$NUMDEVICES" -gt 1 ]]; then
		fscdevice="md127"
		resources="\"md127\",${resources}"
	else
		fscdevice=$(basename "${DEVICESLIST}")
	fi

	echo "Diskio block devices: [${resources}]"
	echo "FS-Cache device: ${fscdevice}"

	jq ".metrics.metrics_collected.diskio.resources = [${resources}] |
		.metrics.metrics_collected.diskio.append_dimensions.fscdevice = \"${fscdevice}\"" \
		"$cw_config" > "${cw_config}.tmp" \
		&& mv "${cw_config}.tmp" "$cw_config"

	echo "CloudWatch Agent diskio configuration updated successfully"
}

# start_metrics() enables the Metrics Agent & CloudWatch Agent
function start_metrics() {
	begin_command "start metrics"
	local cw_pid kma_pid
	# enable metrics if configured
	if [[ ${ENABLE_METRICS} == "true" ]]; then
		echo "Starting Metrics Agents..."
		printf '%s' "${METRICS_AGENT_CONFIG}" > /etc/knfsd-metrics-agent/custom.yaml

		# pre-create the CloudWatch log group used by knfsd-metrics-agent to
		# avoid OperationAbortedException when multiple scrapers concurrently
		# call CreateLogGroup on first boot. Values must match 'config/common.yaml'
		aws logs create-log-group --log-group-name "/knfsd/metrics" \
			--cli-connect-timeout 5 --cli-read-timeout 10 2> /dev/null || true
		aws logs put-retention-policy --log-group-name "/knfsd/metrics" --retention-in-days 30 \
			--cli-connect-timeout 5 --cli-read-timeout 10 2> /dev/null || true

		# first-boot, CW agent converts *.json to *.toml file, so need to check for json file existence
		if [[ -f /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json ]]; then
			update_cloudwatch_diskio_resources
			amazon-cloudwatch-agent-ctl -m ec2 -a fetch-config -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s &
		fi
		cw_pid=$!
		start_services knfsd-metrics-agent &
		kma_pid=$!
		# wait for both agents to finish starting to ensure stdout is grouped within this function
		wait ${cw_pid} ${kma_pid}
		echo "Finished starting Metrics Agents"
	else
		echo "Metrics are disabled. Skipping..."
	fi
	complete_command
}

# post_startup() runs the CUSTOM_POST_STARTUP_SCRIPT
function post_startup() {
	begin_command "post startup"
	if [[ -z "${CUSTOM_POST_STARTUP_SCRIPT:-}" ]]; then
		echo "CUSTOM_POST_STARTUP_SCRIPT is empty; skipping"
	else
		echo "Running CUSTOM_POST_STARTUP_SCRIPT..."
		echo "${CUSTOM_POST_STARTUP_SCRIPT}" | base64 -d | gzip -d > /custom-post-startup-script.sh
		chmod +x /custom-post-startup-script.sh
		bash /custom-post-startup-script.sh
		echo "Finished running CUSTOM_POST_STARTUP_SCRIPT..."
	fi
	complete_command
}

# completed_startup() updates the status to "ready",
# prints the NFS mounts and exports,
# and sets the startup_complete flag to "yes"
function completed_startup() {
	echo -e "${SHELL_YELLOW}### NFS Mounts ###${SHELL_DEFAULT}"
	findmnt -ut nfs,nfs4

	echo -e "${SHELL_YELLOW}### NFS Exports ###${SHELL_DEFAULT}"
	exportfs -s

	# calculate and print total execution time
	local end_time duration hours minutes seconds
	end_time=$(date +%s)
	duration=$((SCRIPT_START_TIME > 0 ? end_time - SCRIPT_START_TIME : 0))
	hours=$((duration / 3600))
	minutes=$(((duration % 3600) / 60))
	seconds=$((duration % 60))

	echo "INFO: Reached Proxy Startup Exit. Happy caching!"
	printf "INFO: %dh%02dm%02ds\n" "$hours" "$minutes" "$seconds"

	update_status "ready"
	startup_complete=yes
}

# Do not call cleanup explicitly, the init function sets an exit trap
function cleanup() {
	local exit_code=$?
	# If the script exits unexpectedly print an error message. This makes it
	# easier when searching the logs to know if the start up script has
	# terminated.
	if [[ $startup_complete != yes ]]; then
		echo -e "${SHELL_RED}" >&2
		echo "ERROR: Failed to start proxy" >&2
		echo "Exit Code: ${exit_code}" >&2

		# capture line number where failure occurred
		if [[ -n "${BASH_LINENO:-}" ]]; then
			echo "Line: ${BASH_LINENO[0]}" >&2
		fi

		# capture the command that failed
		if [[ -n "${BASH_COMMAND:-}" ]]; then
			echo "Failed Command: ${BASH_COMMAND}" >&2
		fi

		# print function stack for context
		if [[ ${#FUNCNAME[@]} -gt 1 ]]; then
			echo "Function Stack:" >&2
			for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
				echo "  ${i}: ${FUNCNAME[$i]} (line ${BASH_LINENO[$((i - 1))]})" >&2
			done
		fi

		# reset color to default
		echo -e "${SHELL_DEFAULT}" >&2

		update_status "error: failed to start proxy" 2> /dev/null || true
	fi

	if [[ -n ${WORKDIR} ]] && [[ -d ${WORKDIR} ]]; then
		rm -rf "${WORKDIR}" || true
	fi

	exit "${exit_code}"
}

# main() is the main function that is called when the script is executed
function main() {
	SCRIPT_START_TIME=$(date +%s)
	init
	pre_startup

	configure_kernel
	configure_network
	create_fs_cache

	echo "MOUNT_OPTIONS: ${MOUNT_OPTIONS}"
	echo "EXPORT_OPTIONS: ${EXPORT_OPTIONS}"

	configure_nfs

	export_map
	export_auto_detect
	export_netapp

	start_fsidd
	start_nfs
	start_metrics

	post_startup
	completed_startup
}

# Do not execute the main() function if this script has been loaded for
# unit testing ($BATS_VERSION is only present if bats is running)
if [[ -z ${BATS_VERSION} ]]; then
	main
fi
