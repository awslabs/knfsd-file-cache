#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT

set -o pipefail

# Terminal colors
SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_BLUE='\033[0;34m'
SHELL_DEFAULT='\033[0m'

METADATA_BASEURL="http://169.254.169.254"
METADATA_TOKEN_PATH="latest/api/token"
QUIET=""

VERSION="1.1.0-alpha.15"

tabs 1

# Check for required utilities
for cmd in sed awk grep curl echo cut wc getopt set; do
	if ! command -v "$cmd" &> /dev/null; then
		echo -e "${SHELL_RED}[ERROR] $cmd is required but not installed. Please install it and try again${SHELL_DEFAULT}" >&2
		exit 1
	fi
done

function print_help() {
	echo "ec2-metadata v${VERSION}
Use to retrieve EC2 instance metadata from within a running EC2 instance.
For more information, see: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html

Usage: ec2-metadata <option>
Options:
	--all                     Show all metadata information for this host (also default).
	-a/--ami-id               The AMI ID used to launch this instance.
	-c/--ami-launch-index     The index of this instance in the reservation (per AMI).
	-b/--block-device-mapping Defines native device names to use when exposing virtual devices.
	-i/--instance-id          The ID of this instance.
	-t/--instance-type        The type of instance to launch. For more information, see Instance Types.
	-h/--local-hostname       The local hostname of the instance.
	-d/--local-ipv4           Public IP address if launched with direct addressing; private IP address if launched with public addressing.
	-z/--availability-zone    The availability zone in which the instance launched. Same as placement.
	-r/--region               The region in which the instance launched.
	-p/--partition            The AWS partition name.
	-e/--product-codes        Product codes associated with this instance.
	-f/--public-hostname      The public hostname of the instance.
	-g/--public-ipv4          NATted public IP Address.
	-j/--public-keys          Public keys. Only available if supplied at instance launch time
	-k/--ramdisk-id           The ID of the RAM disk launched with this instance, if applicable.
	-l/--reservation-id       ID of the reservation.
	-s/--security-groups      Names of the security groups the instance is launched in. Only available if supplied at instance launch time.
	-m/--user-data            User-supplied data. Only available if supplied at instance launch time. (Not included in --all for security reasons)
	-n/--tags                 Tags assigned to this instance.
	-o/--identity-document    JSON containing instance attributes.
	-q/--instance-action      Spot Instance action (if applicable).
	-u/--instance-life-cycle  EC2 instance lifecycle.
	-v/--events               Scheduled events for the instance.
	-w/--network-interfaces   Information about network interfaces.
	-x/--iam                  IAM role information.
	-y/--placement            Instance placement information.
	-I/--ipv6                 IPv6 address of the instance.
	--quiet                   Suppress category keys from the output.
	--no-color                Suppress color output."
}

# Get the IMDSv2 token
function set_imds_token() {
	if [ -z "${IMDS_TOKEN}" ]; then
		# Check if running on EC2 instance
		sys_vendor="/sys/devices/virtual/dmi/id/sys_vendor"
		if [ ! -f "${sys_vendor}" ] || ! grep -q "Amazon" "${sys_vendor}"; then
			echo -e "${SHELL_RED}[ERROR] Instance metadata might have been disabled or this is not an EC2 instance${SHELL_DEFAULT}"
			exit 1
		fi
		if ! IMDS_TOKEN=$(curl -s -f -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 900" ${METADATA_BASEURL}/${METADATA_TOKEN_PATH}); then
			echo -e "${SHELL_RED}[ERROR] Failed to get IMDSv2 token. Exit code: $?${SHELL_DEFAULT}"
			exit 1
		fi

		if [ -z "${IMDS_TOKEN}" ]; then
			echo -e "${SHELL_RED}[ERROR] Could not get IMDSv2 token${SHELL_DEFAULT}"
			exit 1
		fi
	fi
}

# Get metadata from IMDS
function get_meta() {
	local imds_out
	imds_out=$(curl -s -q -H "X-aws-ec2-metadata-token:${IMDS_TOKEN}" -f "${METADATA_BASEURL}/latest/${1}")
	echo -n "${imds_out}"
}

# Print standard metric
function print_normal_metric() {
	metric_path=$2
	[ -z "$QUIET" ] && echo -n "$1: "
	RESPONSE=$(get_meta "${metric_path}")
	if [ -n "${RESPONSE}" ]; then
		echo -e "${SHELL_GREEN}$RESPONSE${SHELL_DEFAULT}"
	else
		echo -e "${SHELL_BLUE}not available${SHELL_DEFAULT}"
	fi
}

# Print block-device-mapping
function print_block-device-mapping() {
	[ -z "$QUIET" ] && echo 'block-device-mapping: '
	x=$(get_meta meta-data/block-device-mapping/)
	if [ -n "${x}" ]; then
		for i in $x; do
			[ -z "$QUIET" ] && echo -ne '\t' "$i: "
			echo -e "${SHELL_GREEN}$(get_meta "meta-data/block-device-mapping/$i")${SHELL_DEFAULT}"
		done
	else
		echo -e "${SHELL_BLUE}not available${SHELL_DEFAULT}"
	fi
}

# Print public-keys
function print_public-keys() {
	[ -z "$QUIET" ] && echo 'public-keys: '
	x=$(get_meta meta-data/public-keys/)
	if [ -n "${x}" ]; then
		for i in $x; do
			index=$(echo "$i" | cut -d = -f 1)
			keyname=$(echo "$i" | cut -d = -f 2)
			[ -z "$QUIET" ] && echo -e "keyname:${SHELL_GREEN}$keyname${SHELL_DEFAULT}"
			[ -z "$QUIET" ] && echo -e "index:${SHELL_GREEN}$index${SHELL_DEFAULT}"
			format=$(get_meta "meta-data/public-keys/$index/")
			[ -z "$QUIET" ] && echo -e "format:${SHELL_GREEN}$format${SHELL_DEFAULT}"
			[ -z "$QUIET" ] && echo 'key:(begins from next line)'
			echo -e "${SHELL_GREEN}$(get_meta "meta-data/public-keys/$index/$format")${SHELL_DEFAULT}"
		done
	else
		echo -e "${SHELL_BLUE}not available${SHELL_DEFAULT}"
	fi
}

# Print tags
function print_tags() {
	[ -z "$QUIET" ] && echo 'tags: '
	x=$(get_meta meta-data/tags/instance/)
	if [ -n "${x}" ]; then
		for i in $x; do
			echo -n -e '\t' "$i: "
			echo -e "${SHELL_GREEN}$(get_meta "meta-data/tags/instance/$i")${SHELL_DEFAULT}"
		done
	else
		echo -e "${SHELL_BLUE}not available${SHELL_DEFAULT}"
	fi
}

# Print identity document
function print_identity_document() {
	[ -z "$QUIET" ] && echo "identity-document: "
	local document
	document=$(get_meta "dynamic/instance-identity/document")
	if [ -n "${document}" ]; then
		echo "${document}" | awk -v green="${SHELL_GREEN}" -v def="${SHELL_DEFAULT}" '
		BEGIN { indent = "  " }
		{
			if ($0 ~ /^{/ || $0 ~ /^}/) {
				print indent def $0;
			} else if (match($0, /^[ \t]*"([^"]+)"[ \t]*:[ \t]*(.*)$/, arr)) {
				gsub(/,$/, "", arr[2]);  # Remove trailing comma if present
				printf "%s%s\"%s\"%s : %s%s%s\n", indent indent, def, arr[1], def, green, arr[2], def;
			} else {
				print indent indent def $0;
			}
		}'
	else
		echo -e "${SHELL_BLUE}not available${SHELL_DEFAULT}"
	fi
}

function print_instance_action() {
	print_normal_metric "instance-action" "spot/instance-action"
}

function print_instance_life_cycle() {
	print_normal_metric "instance-life-cycle" "meta-data/instance-life-cycle"
}

function print_events() {
	print_normal_metric "events" "meta-data/events/maintenance/scheduled"
}

# Print network interfaces
function print_network_interfaces() {
	[ -z "$QUIET" ] && echo 'network-interfaces: '
	local interfaces
	interfaces=$(get_meta meta-data/network/interfaces/macs/)
	if [ -n "${interfaces}" ]; then
		for interface in $interfaces; do
			echo -e '\t' "MAC: ${SHELL_GREEN}$interface${SHELL_DEFAULT}"
			echo -e '\t\t' "  Device Number: ${SHELL_GREEN}$(get_meta "meta-data/network/interfaces/macs/${interface}/device-number")${SHELL_DEFAULT}"
			echo -e '\t\t' "  Interface ID: ${SHELL_GREEN}$(get_meta "meta-data/network/interfaces/macs/${interface}/interface-id")${SHELL_DEFAULT}"

			# Function to print aligned addresses
			print_aligned_addresses() {
				local label=$1
				local addresses=$2
				if [[ $(echo "$addresses" | wc -l) -gt 1 ]]; then
					echo -e '  ' "  $label:"
					echo -e "${SHELL_GREEN}$addresses${SHELL_DEFAULT}" | sed 's/^/      /'
				else
					echo -e '\t\t' "  $label: ${SHELL_GREEN}$addresses${SHELL_DEFAULT}"
				fi
			}

			print_aligned_addresses "Local IPv4s" "$(get_meta "meta-data/network/interfaces/macs/${interface}/local-ipv4s")"
			print_aligned_addresses "Public IPv4s" "$(get_meta "meta-data/network/interfaces/macs/${interface}/public-ipv4s")"
			print_aligned_addresses "IPv6s" "$(get_meta "meta-data/network/interfaces/macs/${interface}/ipv6s")"
		done
	else
		echo -e "${SHELL_BLUE}not available${SHELL_DEFAULT}"
	fi
}

# Print IAM info
function print_iam() {
	[ -z "$QUIET" ] && echo 'iam: '
	local info
	info=$(get_meta meta-data/iam/info)
	if [ -n "${info}" ]; then
		echo "${info}" | awk -v green="${SHELL_GREEN}" -v def="${SHELL_DEFAULT}" '
		BEGIN { indent = "  " }
		{
			if ($0 ~ /^{/ || $0 ~ /^}/) {
				print indent def $0;
			} else if (match($0, /^[ \t]*"([^"]+)"[ \t]*:[ \t]*(.*)$/, arr)) {
				gsub(/,$/, "", arr[2]);  # Remove trailing comma if present
				printf "%s%s\"%s\"%s : %s%s%s\n", indent indent, def, arr[1], def, green, arr[2], def;
			} else {
				print indent indent def $0;
			}
		}'
	else
		echo -e "${SHELL_BLUE}not available${SHELL_DEFAULT}"
	fi
}

# Print placement info
function print_placement() {
	[ -z "$QUIET" ] && echo 'placement: '
	echo -e '\t' "Availability Zone: ${SHELL_GREEN}$(get_meta meta-data/placement/availability-zone)${SHELL_DEFAULT}"
	echo -e '\t' "Availability Zone ID: ${SHELL_GREEN}$(get_meta meta-data/placement/availability-zone-id)${SHELL_DEFAULT}"
	echo -e '\t' "Region: ${SHELL_GREEN}$(get_meta meta-data/placement/region)${SHELL_DEFAULT}"
	echo -e '\t' "Host ID: ${SHELL_GREEN}$(get_meta meta-data/placement/host-id)${SHELL_DEFAULT}"
	echo -e '\t' "Partition Number: ${SHELL_GREEN}$(get_meta meta-data/placement/partition-number)${SHELL_DEFAULT}"
}

function print_ipv6() {
	print_normal_metric "ipv6" "meta-data/ipv6"
}

# Print all metadata
function print_all() {
	print_normal_metric ami-id meta-data/ami-id
	print_normal_metric ami-launch-index meta-data/ami-launch-index
	print_block-device-mapping
	print_normal_metric instance-id meta-data/instance-id
	print_normal_metric instance-type meta-data/instance-type
	print_normal_metric local-hostname meta-data/local-hostname
	print_normal_metric local-ipv4 meta-data/local-ipv4
	print_normal_metric placement meta-data/placement/availability-zone
	print_normal_metric region meta-data/placement/region
	print_normal_metric partition meta-data/services/partition
	print_normal_metric product-codes meta-data/product-codes
	print_normal_metric public-hostname meta-data/public-hostname
	print_normal_metric public-ipv4 meta-data/public-ipv4
	print_normal_metric ramdisk-id /meta-data/ramdisk-id
	print_normal_metric reservation-id /meta-data/reservation-id
	print_normal_metric security-groups meta-data/security-groups
	print_tags
	print_identity_document
	print_instance_action
	print_instance_life_cycle
	print_events
	print_network_interfaces
	print_iam
	print_placement
	print_ipv6
}

# Check if run inside an EC2 instance
set_imds_token

# Command called in default mode
if [ "$#" -eq 0 ]; then
	print_all
fi

declare -a actions
shortopts=acbithdzrpefgjklsmnoquvwxyI
longopts=(all ami-id ami-launch-index block-device-mapping
	instance-id instance-type local-hostname local-ipv4 availability-zone
	region partition product-codes public-hostname public-ipv4 public-keys
	ramdisk-id reservation-id security-groups user-data tags identity-document
	instance-action instance-life-cycle events network-interfaces iam placement
	ipv6 quiet no-color no-colour help)

oldIFS="$IFS"
IFS=,
if ! TEMP=$(getopt -o $shortopts --longoptions "${longopts[*]}" -n 'ec2-metadata' -- "$@"); then
	echo 'Exiting...' >&2
	exit 1
fi
IFS="$oldIFS"

eval set -- "$TEMP"
unset TEMP

while true; do
	case "$1" in
		--help)
			print_help
			shift
			exit 0
			;;
		--quiet)
			QUIET=1
			shift
			;;
		--no-color | --no-colour)
			SHELL_RED='\033[0m'
			SHELL_GREEN='\033[0m'
			SHELL_BLUE='\033[0m'
			shift
			;;
		--)
			shift
			break
			;;
		--?* | -?)
			actions+=("$1")
			shift
			;;
		*)
			echo 'Unknown error: ' "[$1]" >&2
			exit 1
			;;
	esac
done

# Start processing command line arguments
for action in "${actions[@]}"; do
	case "$action" in
		-a | --ami-id) print_normal_metric ami-id meta-data/ami-id ;;
		-c | --ami-launch-index) print_normal_metric ami-launch-index meta-data/ami-launch-index ;;
		-b | --block-device-mapping) print_block-device-mapping ;;
		-i | --instance-id) print_normal_metric instance-id meta-data/instance-id ;;
		-t | --instance-type) print_normal_metric instance-type meta-data/instance-type ;;
		-h | --local-hostname) print_normal_metric local-hostname meta-data/local-hostname ;;
		-d | --local-ipv4) print_normal_metric local-ipv4 meta-data/local-ipv4 ;;
		-z | --availability-zone) print_normal_metric placement meta-data/placement/availability-zone ;;
		-r | --region) print_normal_metric region meta-data/placement/region ;;
		-p | --partition) print_normal_metric partition meta-data/services/partition ;;
		-e | --product-codes) print_normal_metric product-codes meta-data/product-codes ;;
		-f | --public-hostname) print_normal_metric public-hostname meta-data/public-hostname ;;
		-g | --public-ipv4) print_normal_metric public-ipv4 meta-data/public-ipv4 ;;
		-j | --public-keys) print_public-keys ;;
		-k | --ramdisk-id) print_normal_metric ramdisk-id /meta-data/ramdisk-id ;;
		-l | --reservation-id) print_normal_metric reservation-id /meta-data/reservation-id ;;
		-s | --security-groups) print_normal_metric security-groups meta-data/security-groups ;;
		-m | --user-data) print_normal_metric user-data user-data ;;
		-n | --tags) print_tags ;;
		-o | --identity-document) print_identity_document ;;
		-q | --instance-action) print_instance_action ;;
		-u | --instance-life-cycle) print_instance_life_cycle ;;
		-v | --events) print_events ;;
		-w | --network-interfaces) print_network_interfaces ;;
		-x | --iam) print_iam ;;
		-y | --placement) print_placement ;;
		-I | --ipv6) print_ipv6 ;;
		--all)
			print_all
			exit 0
			;;
	esac
	shift
done

exit 0
