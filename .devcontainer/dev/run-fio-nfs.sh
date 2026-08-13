#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## FIO NFS
## Provisions a "captain" (FIO client) and N "client" instances (FIO servers)
## that mount a KNFSD proxy and run FIO in client/server mode.

## USAGE:
## ./run-fio-nfs.sh help|-h|--help
## ./run-fio-nfs.sh status
## ./run-fio-nfs.sh apply --knfsd-ip <IP> --subnet <ID> --security-group-id <ID> [OPTIONS]
## ./run-fio-nfs.sh apply --knfsd-ip <IP> --subnet <ID> --security-group-id <ID> [--key-name <KEYPAIR_NAME>] [OPTIONS]
## ./run-fio-nfs.sh scale --num-clients <N> --knfsd-ip <IP> --subnet <ID> --security-group-id <ID> [OPTIONS]
## ./run-fio-nfs.sh run --fio-job <fio/nfs-fscache-deadlock/create-files.fio> [OPTIONS]
## ./run-fio-nfs.sh run --fio-job <fio/nfs-fscache-deadlock/run-test.fio> [OPTIONS]
## ./run-fio-nfs.sh run --fio-job <FIO_JOB_FILE> [--tunnel <eice|ssm>] [OPTIONS]
## ./run-fio-nfs.sh run --fio-job <FIO_JOB_FILE> [--instance-connect-endpoint-id <EICE_ID> --key-name <KEYPAIR_NAME>] [OPTIONS]
## ./run-fio-nfs.sh destroy

## KNFSD-IP
## CRITICAL: The SECONDARY ENI (Device Index: 1, "ens6") PRIVATE IP address of the KNFSD proxy must be used here.
## Do NOT use the PRIMARY ENI (Device Index: 0, "ens5") PRIVATE IP address.

## SUBNET
## Ideally this should be the same subnet as the KNFSD proxy

## SECURITY-GROUP-ID
## TCP:8765 is required for FIO communication between clients and captain

## CUSTOM KEYPAIR:
## If you want to use a custom EC2 keypair, you can pass the --key-name <KEYPAIR_NAME> option to the "apply" and "run" commands.
## The keypair must match the private key identified by shell variable: IDENTITY_FILE=<path> [default: ~/.ssh/id_rsa]

## PRIVATE SUBNET:
## If FIO captain is in a private subnet (no public IP assigned), the SSH connection must be tunnelled.
## Select the tunnel type with --tunnel on the "run" command only (default: eice):
##
## eice: manually create an EC2 Instance Connect Endpoint (EICE) in your VPC
##   aws ec2 create-instance-connect-endpoint --subnet-id <subnet-id>
## then pass the EICE ID to the "run" command only:
##   ./run-fio-nfs.sh run --fio-job <FIO_JOB_FILE> --instance-connect-endpoint-id <EICE_ID> [--key-name <KEYPAIR_NAME>] [OPTIONS]
## AWS docs: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html
##
## ssm: no endpoint to create, requires the "session-manager-plugin" installed locally:
##   ./run-fio-nfs.sh run --fio-job <FIO_JOB_FILE> --tunnel ssm [--key-name <KEYPAIR_NAME>] [OPTIONS]
## The captain's IAM instance profile (IAM_PROFILE_NAME, default "knfsd-instance-role") must allow the
## AWS SSM agent actions; the KNFSD instance role already attaches "AmazonSSMManagedInstanceCore".
## AWS SSM reachability is also required (NAT or the ssm, ssmmessages and ec2messages VPC endpoints).
## AWS docs: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

## More info: https://github.com/awslabs/knfsd-file-cache/blob/main/docs/developer.md#remote-ssh-considerations

## fscache deadlock notes:
## 1. ./run-fio-nfs.sh apply --knfsd-ip <IP> --subnet <ID> --security-group-id <ID>
## 2. ./run-fio-nfs.sh run --fio-job fio/nfs-fscache-deadlock/create-files.fio (6.3TB ~41 mins)
## 3. SSH into KNFSD proxy (add EC2 Security Group if applicable to allow access):
##    sudo systemctl stop cachefilesd
##    sudo rm -rf /var/cache/fscache/*
##    sudo systemctl start cachefilesd
##    echo 3 | sudo tee /proc/sys/vm/drop_caches
##    sudo stress-ng --vm 8 --vm-bytes 95% --vm-method all --timeout 120m --oom-avoid
## 4. ./run-fio-nfs.sh run --fio-job fio/nfs-fscache-deadlock/run-test.fio (120 mins)
## 5. SSH into KNFSD proxy (wait for crash):
##    sudo dmesg -w
## 6. Success: KNFSD instance does not crash, possible log messages using XFS (but no crash):
## 	[x] workqueue: irq_affinity_notify hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND
## 	[x] workqueue: xfs_inodegc_worker [xfs] hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND
## 	[x] workqueue: xlog_ioend_work [xfs] hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND
## 	[x] workqueue: iomap_dio_complete_work hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND
## 	[x] workqueue: xfs_btree_split_worker [xfs] hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND
## 	[x] systemd-journald[303]: Under memory pressure, flushing caches.

set -eo pipefail

VERSION="1.1.0-beta.2"

# terminal colors
SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_BLUE='\033[0;34m'
SHELL_DEFAULT='\033[0m'

# AMI settings (Ubuntu SSM parameters)
PRODUCT="server"
RELEASE="26.04"
ARCH="amd64"
VOL_TYPE="ebs-gp3"

# FIO captain always uses arm64
CAPTAIN_ARCH="arm64"
CAPTAIN_INSTANCE_TYPE="t4g.large"

# FIO version (built from source)
FIO_VERSION="3.41"

# defaults (overridable by CLI)
NUM_CLIENTS=10
INSTANCE_TYPE="c6i.8xlarge"
AMI_ID=""
SUBNET=""
SG_ID=""
IAM_PROFILE_NAME="knfsd-instance-role"
MOUNT_PATH="/mnt/fsx"
MOUNT_EXPORT="/fsx"
FIO_JOB=""
KNFSD_IP=""
EICE_ID=""
KEY_NAME=""
# tunnel type used to reach the captain: eice (default) or ssm
TUNNEL="eice"
# max seconds to wait for the captain's AWS SSM agent to register
SSM_WAIT_TIMEOUT=300

# AWS "name" tag for all instances (captain + clients)
FIO_TAG_PREFIX="knfsd-fio"
CAPTAIN_NAME="${FIO_TAG_PREFIX}-captain"
CLIENT_NAME_PREFIX="${FIO_TAG_PREFIX}-client"

USERNAME="ubuntu"
IDENTITY_FILE="${HOME}/.ssh/id_rsa"

function usage() {
	cat >&2 << EOT
FIO NFS Benchmarking
Ensure AWS credentials/region are configured.

Commands:
	./run-fio-nfs.sh help|-h|--help
		Show this message.
	./run-fio-nfs.sh apply --knfsd-ip <IP> --subnet <ID> --security-group-id <ID> [OPTIONS]
		Provision captain (t4g.small arm64) and N FIO server instances.
		--knfsd-ip is required (KNFSD proxy IP for NFS mounts).
		--subnet is required (ID of the subnet to launch the instances in).
		--security-group-id is required (ID of the security group to launch the instances in).
		Optional: --key-name <KEYPAIR_NAME> attaches an EC2 keypair to the captain instance. Must match private key identified by: IDENTITY_FILE=<path>
	./run-fio-nfs.sh scale --num-clients <N> --knfsd-ip <IP> --subnet <ID> --security-group-id <ID> [OPTIONS]
		Add N additional FIO client instances to an existing fleet.
		Requires an existing captain (run apply first).
	./run-fio-nfs.sh run [OPTIONS] [--tunnel <eice|ssm>] [--instance-connect-endpoint-id <EICE_ID>] [--key-name <KEYPAIR_NAME>]
		Copy job file to captain, run FIO client/server test,
		and download results. Use --fio-job to select the job file.
		Default: fio/nfs-fscache-deadlock/run-test.fio (deadlock test).
		Optional: --key-name <KEYPAIR_NAME> uses keypair auth (skips send-ssh-public-key); must match private key identified by: IDENTITY_FILE=<path>
		For captain in a private subnet (no public IP), the SSH connection is tunnelled.
		Optional: --tunnel <eice|ssm> selects the tunnel type [default: eice].
		For the eice tunnel, pass --instance-connect-endpoint-id <EICE_ID> to run only (not apply/scale/status/destroy).
		The ssm tunnel needs no endpoint, but requires the "session-manager-plugin" installed locally.
		Example: create source files first:
			./run-fio-nfs.sh run --fio-job fio/nfs-fscache-deadlock/create-files.fio
		then run deadlock test (default job):
			./run-fio-nfs.sh run
		Results are saved as: fio-output-<jobname>-YYYYMMDD-HHMMSS.json
	./run-fio-nfs.sh destroy
		Terminate all knfsd-fio-* instances (captain + clients).
	./run-fio-nfs.sh status
		List knfsd-fio-* instances with state and IP.
EOT
}

# get_ami_id returns AMI ID for given arch (amd64 or arm64)
function get_ami_id() {
	local arch="$1"
	aws ssm get-parameter \
		--name "/aws/service/canonical/ubuntu/${PRODUCT}/${RELEASE}/stable/current/${arch}/hvm/${VOL_TYPE}/ami-id" \
		--query 'Parameter.Value' \
		--output text
}

function parse_args() {
	function require_option_value() {
		local option_name="$1"
		local option_value="${2:-}"
		if [[ -z "${option_value}" || "${option_value}" == --* ]]; then
			echo -e "${SHELL_RED}ERROR: Missing value for ${option_name}${SHELL_DEFAULT}" >&2
			exit 1
		fi
	}

	# set script dir to directory containing this script
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	FIO_JOB="${SCRIPT_DIR}/fio/nfs-fscache-deadlock/run-test.fio"

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--knfsd-ip)
				require_option_value "$1" "${2:-}"
				KNFSD_IP="$2"
				shift 2
				;;
			--subnet)
				require_option_value "$1" "${2:-}"
				SUBNET="$2"
				shift 2
				;;
			--security-group-id)
				require_option_value "$1" "${2:-}"
				SG_ID="$2"
				shift 2
				;;
			--num-clients)
				require_option_value "$1" "${2:-}"
				NUM_CLIENTS="$2"
				shift 2
				;;
			--instance-type)
				require_option_value "$1" "${2:-}"
				INSTANCE_TYPE="$2"
				shift 2
				;;
			--ami-id)
				require_option_value "$1" "${2:-}"
				AMI_ID="$2"
				shift 2
				;;
			--mount-path)
				require_option_value "$1" "${2:-}"
				MOUNT_PATH="$2"
				shift 2
				;;
			--mount-export)
				require_option_value "$1" "${2:-}"
				MOUNT_EXPORT="$2"
				shift 2
				;;
			--fio-job)
				require_option_value "$1" "${2:-}"
				FIO_JOB="$2"
				shift 2
				;;
			--instance-connect-endpoint-id)
				require_option_value "$1" "${2:-}"
				EICE_ID="$2"
				shift 2
				;;
			--tunnel)
				require_option_value "$1" "${2:-}"
				TUNNEL="$2"
				if [[ "${TUNNEL}" != "eice" && "${TUNNEL}" != "ssm" ]]; then
					echo -e "${SHELL_RED}ERROR: --tunnel must be 'eice' or 'ssm' (got: ${TUNNEL})${SHELL_DEFAULT}" >&2
					exit 1
				fi
				shift 2
				;;
			--key-name)
				require_option_value "$1" "${2:-}"
				KEY_NAME="$2"
				shift 2
				;;
			--help | -h | help | "")
				usage
				exit 0
				;;
			*)
				echo -e "${SHELL_RED}ERROR: Unknown option: $1${SHELL_DEFAULT}" >&2
				usage
				exit 1
				;;
		esac
	done
}

# create_user_data_client outputs user-data script for FIO server (NFS client) instances
function create_user_data_client() {
	cat << EOT
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get -y -q update
apt-get -y -q install -o=Dpkg::Use-Pty=0 build-essential libaio-dev nfs-common
cd /tmp
curl -fsSL "https://github.com/axboe/fio/archive/refs/tags/fio-${FIO_VERSION}.tar.gz" -o fio.tar.gz
tar xzf fio.tar.gz
cd fio-fio-${FIO_VERSION}
./configure
make -j\$(nproc)
make install
cd /tmp
if ! snap debug seeding | grep -q "^seeded: *true\$"; then
	timeout 300 sh -c 'until snap debug seeding | grep -q "^seeded: *true\$"; do sleep 5; done'
fi
snap install aws-cli --classic
mkdir -p ${MOUNT_PATH}
mount -t nfs -o vers=3,tcp,noatime,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${KNFSD_IP}:${MOUNT_EXPORT} ${MOUNT_PATH}
mkdir -p ${MOUNT_PATH}/fio
fio --server --daemonize=/var/run/fio.pid
REGION=\$(cloud-init query region)
INSTANCE_ID=\$(cloud-init query instance_id)
aws ec2 create-tags --region "\${REGION}" --resources "\${INSTANCE_ID}" --tags "Key=knfsd-file-cache:status,Value=ready"
EOT
}

# create_user_data_captain outputs user-data script for captain (FIO client) instance
function create_user_data_captain() {
	cat << EOT
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get -y -q update
apt-get -y -q install -o=Dpkg::Use-Pty=0 build-essential libaio-dev
cd /tmp
curl -fsSL "https://github.com/axboe/fio/archive/refs/tags/fio-${FIO_VERSION}.tar.gz" -o fio.tar.gz
tar xzf fio.tar.gz
cd fio-fio-${FIO_VERSION}
./configure
make -j\$(nproc)
make install
cd /tmp
if ! snap debug seeding | grep -q "^seeded: *true\$"; then
	timeout 300 sh -c 'until snap debug seeding | grep -q "^seeded: *true\$"; do sleep 5; done'
fi
snap install aws-cli --classic
REGION=\$(cloud-init query region)
INSTANCE_ID=\$(cloud-init query instance_id)
aws ec2 create-tags --region "\${REGION}" --resources "\${INSTANCE_ID}" --tags "Key=knfsd-file-cache:status,Value=ready"
EOT
}

# resolve_client_ami resolves and validates the client AMI ID, prints it to stdout.
function resolve_client_ami() {
	local client_ami_id
	if [[ -n "${AMI_ID}" ]]; then
		client_ami_id="${AMI_ID}"
	else
		client_ami_id=$(get_ami_id "${ARCH}")
	fi

	local ami_id_regex="^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$"
	if [[ ! ${client_ami_id} =~ ${ami_id_regex} ]]; then
		echo -e "${SHELL_RED}ERROR: invalid client ami-id: ${client_ami_id}${SHELL_DEFAULT}" >&2
		exit 1
	fi
	# output to stdout for capture by caller: client_ami_id=$(resolve_client_ami)
	echo "${client_ami_id}"
}

# launch_clients launches N client instances and tags them sequentially from start_idx.
# Prints space-separated instance IDs to stdout.
function launch_clients() {
	local client_ami_id="$1"
	local start_idx="$2"

	local root_device_name
	root_device_name=$(aws ec2 describe-images --image-ids "${client_ami_id}" \
		--query 'Images[0].RootDeviceName' --output text)

	local client_ud
	client_ud=$(create_user_data_client)

	local client_ids
	client_ids=$(aws ec2 run-instances \
		--image-id "${client_ami_id}" \
		--instance-type "${INSTANCE_TYPE}" \
		--subnet-id "${SUBNET}" \
		--security-group-ids "${SG_ID}" \
		--iam-instance-profile "Name=${IAM_PROFILE_NAME}" \
		--block-device-mappings "[{\"DeviceName\":\"${root_device_name}\",\"Ebs\":{\"VolumeSize\":20,\"VolumeType\":\"gp3\",\"Encrypted\":true}}]" \
		--user-data "${client_ud}" \
		--metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=2,InstanceMetadataTags=enabled" \
		--count "${NUM_CLIENTS}" \
		--tag-specifications "ResourceType=instance,Tags=[{Key=knfsd-file-cache:version,Value=${VERSION}},{Key=knfsd-fio,Value=client}]" \
		--query 'Instances[].InstanceId' --output text)

	# Tag client names (knfsd-fio-client-001, knfsd-fio-client-002, ...)
	local idx=${start_idx}
	for iid in ${client_ids}; do
		local idx_pad
		printf -v idx_pad '%03d' "${idx}"
		aws ec2 create-tags --resources "${iid}" \
			--tags "Key=Name,Value=${CLIENT_NAME_PREFIX}-${idx_pad}"
		idx=$((idx + 1))
	done

	echo "${client_ids}"
}

function cmd_apply() {
	if [[ -z "${KNFSD_IP}" || -z "${SUBNET}" || -z "${SG_ID}" ]]; then
		echo -e "${SHELL_RED}ERROR: --knfsd-ip, --subnet and --security-group-id are required for apply${SHELL_DEFAULT}" >&2
		exit 1
	fi

	# Check for existing fleet
	local existing
	existing=$(aws ec2 describe-instances \
		--filters "Name=tag:Name,Values=${CAPTAIN_NAME}" "Name=instance-state-name,Values=pending,running" \
		--query 'Reservations[].Instances[].InstanceId' --output text 2> /dev/null)
	if [[ -n "${existing}" ]]; then
		echo -e "${SHELL_RED}ERROR: ${CAPTAIN_NAME} already exists (${existing}). Run destroy first.${SHELL_DEFAULT}" >&2
		exit 1
	fi

	local client_ami_id
	client_ami_id=$(resolve_client_ami)

	# Launch captain
	local captain_ami_id
	captain_ami_id=$(get_ami_id "${CAPTAIN_ARCH}")
	local ami_id_regex="^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$"
	if [[ ! ${captain_ami_id} =~ ${ami_id_regex} ]]; then
		echo -e "${SHELL_RED}ERROR: invalid captain ami-id: ${captain_ami_id}${SHELL_DEFAULT}" >&2
		exit 1
	fi

	local captain_ud
	captain_ud=$(create_user_data_captain)

	local captain_extra_args=()
	if [[ -n "${KEY_NAME}" ]]; then
		captain_extra_args+=(--key-name "${KEY_NAME}")
	fi

	local captain_id
	captain_id=$(aws ec2 run-instances \
		--image-id "${captain_ami_id}" \
		--instance-type "${CAPTAIN_INSTANCE_TYPE}" \
		--subnet-id "${SUBNET}" \
		--security-group-ids "${SG_ID}" \
		--iam-instance-profile "Name=${IAM_PROFILE_NAME}" \
		--user-data "${captain_ud}" \
		--metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=2,InstanceMetadataTags=enabled" \
		--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${CAPTAIN_NAME}},{Key=knfsd-file-cache:version,Value=${VERSION}},{Key=knfsd-fio,Value=captain}]" \
		"${captain_extra_args[@]}" \
		--query 'Instances[0].InstanceId' --output text)

	# Launch clients
	local client_ids
	client_ids=$(launch_clients "${client_ami_id}" 1)

	echo -e "Captain: ${SHELL_GREEN}${captain_id}${SHELL_DEFAULT}"
	echo -e "Clients (${NUM_CLIENTS}):"
	for iid in ${client_ids}; do
		echo -e "  ${SHELL_GREEN}${iid}${SHELL_DEFAULT}"
	done

	# Wait for instances to be running
	aws ec2 wait instance-running --instance-ids "${captain_id}" ${client_ids}
	cmd_status
}

# push_ssh_key pushes the local SSH public key to an instance via EC2 Instance Connect.
# The key is only valid for 60 seconds, so call this before each SSH/SCP operation.
function push_ssh_key() {
	local instance_id="$1"
	aws ec2-instance-connect send-ssh-public-key \
		--instance-id "${instance_id}" \
		--instance-os-user "${USERNAME}" \
		--ssh-public-key "file://${IDENTITY_FILE}.pub" > /dev/null
	sleep 2
}

# wait_for_ssm_online polls AWS SSM until the instance's agent reports PingStatus
# "Online". An SSM tunnel cannot be opened until the agent has registered.
function wait_for_ssm_online() {
	local instance_id="$1"
	local deadline=$((SECONDS + SSM_WAIT_TIMEOUT))
	local ping_status=""
	echo -e "${SHELL_BLUE}Waiting for AWS SSM agent on ${instance_id} to report Online...${SHELL_DEFAULT}"
	while ((SECONDS < deadline)); do
		ping_status=$(aws ssm describe-instance-information \
			--filters "Key=InstanceIds,Values=${instance_id}" \
			--query 'InstanceInformationList[0].PingStatus' \
			--output text 2> /dev/null) || ping_status=""
		if [[ "${ping_status}" == "Online" ]]; then
			return 0
		fi
		sleep 5
	done
	echo -e "${SHELL_RED}ERROR: timed out after ${SSM_WAIT_TIMEOUT}s waiting for AWS SSM agent on ${instance_id}${SHELL_DEFAULT}" >&2
	return 1
}

# get_captain_instance_id prints the captain instance ID (or empty)
function get_captain_instance_id() {
	aws ec2 describe-instances \
		--filters "Name=tag:Name,Values=${CAPTAIN_NAME}" "Name=instance-state-name,Values=running,pending" \
		--query 'Reservations[].Instances[].InstanceId' --output text 2> /dev/null
}

# get_client_private_dns returns space-separated private DNS names of FIO client instances (sorted by Name tag)
function get_client_private_dns() {
	aws ec2 describe-instances \
		--filters "Name=tag:knfsd-fio,Values=client" "Name=instance-state-name,Values=running" \
		--query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], PrivateDnsName]' \
		--output text 2> /dev/null | sort -t$'\t' -k1,1V | cut -f2
}

function cmd_scale() {
	if [[ -z "${NUM_CLIENTS}" || -z "${KNFSD_IP}" || -z "${SUBNET}" || -z "${SG_ID}" ]]; then
		echo -e "${SHELL_RED}ERROR: --num-clients, --knfsd-ip, --subnet and --security-group-id are required for scale${SHELL_DEFAULT}" >&2
		exit 1
	fi

	# Verify captain exists
	local captain_id
	captain_id=$(get_captain_instance_id)
	if [[ -z "${captain_id}" ]]; then
		echo -e "${SHELL_RED}ERROR: No running ${CAPTAIN_NAME} found. Run apply first.${SHELL_DEFAULT}" >&2
		exit 1
	fi

	# Find highest existing client index (parse 001, 002, 010 as decimal)
	local max_idx=0
	local existing_names
	existing_names=$(aws ec2 describe-instances \
		--filters "Name=tag:knfsd-fio,Values=client" "Name=instance-state-name,Values=pending,running" \
		--query 'Reservations[].Instances[].Tags[?Key==`Name`].Value[]' \
		--output text 2> /dev/null) || true
	for n in ${existing_names}; do
		local idx_str="${n##*-}"
		if [[ "${idx_str}" =~ ^[0-9]+$ ]]; then
			local idx_num=$((10#${idx_str}))
			if ((idx_num > max_idx)); then
				max_idx=${idx_num}
			fi
		fi
	done
	echo -e "${SHELL_BLUE}Existing clients: ${max_idx}, adding ${NUM_CLIENTS} more...${SHELL_DEFAULT}"

	local client_ami_id
	client_ami_id=$(resolve_client_ami)

	local client_ids
	client_ids=$(launch_clients "${client_ami_id}" $((max_idx + 1)))

	echo -e "New clients (${NUM_CLIENTS}):"
	for iid in ${client_ids}; do
		echo -e "  ${SHELL_GREEN}${iid}${SHELL_DEFAULT}"
	done

	# Wait for new instances to be running
	aws ec2 wait instance-running --instance-ids ${client_ids}
	cmd_status
}

function cmd_run() {
	local captain_id
	captain_id=$(get_captain_instance_id)
	if [[ -z "${captain_id}" ]]; then
		echo -e "${SHELL_RED}ERROR: No running ${CAPTAIN_NAME} found. Run apply first.${SHELL_DEFAULT}" >&2
		exit 1
	fi

	local clients
	mapfile -t clients < <(get_client_private_dns)
	if [[ ${#clients[@]} -eq 0 ]]; then
		echo -e "${SHELL_RED}ERROR: No running FIO client instances found. Run apply first.${SHELL_DEFAULT}" >&2
		exit 1
	fi

	# resolve relative path to script directory
	if [[ "${FIO_JOB}" != /* ]]; then
		FIO_JOB="${SCRIPT_DIR}/${FIO_JOB}"
	fi

	if [[ ! -f "${FIO_JOB}" ]]; then
		echo -e "${SHELL_RED}ERROR: FIO job file not found: ${FIO_JOB}${SHELL_DEFAULT}" >&2
		exit 1
	fi

	if [[ ! -f "${IDENTITY_FILE}" || ! -f "${IDENTITY_FILE}.pub" ]]; then
		echo -e "${SHELL_RED}ERROR: SSH key pair not found: ${IDENTITY_FILE} / ${IDENTITY_FILE}.pub${SHELL_DEFAULT}" >&2
		exit 1
	fi

	local remote_output="/tmp/fio-output.json"

	# Build per-client job files with filename_format to route files into client-specific subdirectories.
	# FIO creates subdirectories from literal paths in filename_format (directory=/mnt/fsx/fio must exist).
	local idx=1
	local gen_jobs=""
	local fio_args=""
	for client in "${clients[@]}"; do
		local idx_pad
		printf -v idx_pad '%03d' "${idx}"
		gen_jobs+="cp fio-settings.fio fio-client-${idx_pad}.fio"$'\n'
		gen_jobs+="echo 'filename_format=client-${idx_pad}/\$jobname.\$jobnum.\$filenum' >> fio-client-${idx_pad}.fio"$'\n'
		fio_args+="--client=${client} fio-client-${idx_pad}.fio "
		idx=$((idx + 1))
	done

	# SSH/SCP options for tunnelling to the captain
	local proxy_cmd
	if [[ "${TUNNEL}" == "ssm" ]]; then
		if ! command -v session-manager-plugin > /dev/null 2>&1; then
			echo -e "${SHELL_RED}ERROR: 'session-manager-plugin' not found in PATH${SHELL_DEFAULT}" >&2
			exit 1
		fi
		# %h resolves to the instance-id (the ssh "host") and %p to the port (22)
		proxy_cmd="aws ssm start-session --target %h"
		proxy_cmd="${proxy_cmd} --document-name AWS-StartSSHSession"
		proxy_cmd="${proxy_cmd} --parameters portNumber=%p"
		wait_for_ssm_online "${captain_id}"
	else
		proxy_cmd="aws ec2-instance-connect open-tunnel --instance-id %h"
		if [[ -n "${EICE_ID}" ]]; then
			proxy_cmd="${proxy_cmd} --instance-connect-endpoint-id ${EICE_ID}"
		fi
	fi
	local opts=(
		-i "${IDENTITY_FILE}"
		-o "StrictHostKeyChecking=no"
		-o "UserKnownHostsFile=/dev/null"
		-o "LogLevel=ERROR"
		-o "ProxyCommand=${proxy_cmd}"
	)

	echo -e "${SHELL_BLUE}Copying job file to captain...${SHELL_DEFAULT}"
	if [[ -z "${KEY_NAME}" ]]; then
		push_ssh_key "${captain_id}"
	fi
	scp "${opts[@]}" "${FIO_JOB}" "${USERNAME}@${captain_id}:/tmp/fio-settings.fio"

	echo -e "${SHELL_BLUE}Running FIO...${SHELL_DEFAULT}"
	if [[ -z "${KEY_NAME}" ]]; then
		push_ssh_key "${captain_id}"
	fi
	local fio_rc=0

	# shellcheck disable=SC2087
	ssh "${opts[@]}" "${USERNAME}@${captain_id}" bash -s << REMOTE || fio_rc=$?
		cd /tmp
		rm -f fio-client-*.fio fio-output.json
		${gen_jobs}
		fio --output-format=json ${fio_args} | tee ${remote_output}
		fio_exit=\${PIPESTATUS[0]}
		if [ "\${fio_exit}" -ne 0 ]; then
			echo ""
			echo -e "${SHELL_RED}ERROR: FIO exited with code \${fio_exit}${SHELL_DEFAULT}" >&2
			exit "\${fio_exit}"
		fi
REMOTE

	if [[ ${fio_rc} -ne 0 ]]; then
		echo -e "${SHELL_RED}ERROR: FIO test failed (exit code ${fio_rc}). Skipping results download.${SHELL_DEFAULT}" >&2
		return 1
	fi

	local job_name
	job_name=$(basename "${FIO_JOB}" .fio)
	local timestamp
	timestamp=$(date +%Y%m%d-%H%M%S)
	local local_output="fio-output-${job_name}-${timestamp}.json"

	echo -e "${SHELL_BLUE}Transferring results...${SHELL_DEFAULT}"
	if [[ -z "${KEY_NAME}" ]]; then
		push_ssh_key "${captain_id}"
	fi
	scp "${opts[@]}" "${USERNAME}@${captain_id}:${remote_output}" "./${local_output}"
	echo -e "${SHELL_GREEN}Results saved to: $(pwd)/${local_output}${SHELL_DEFAULT}"
}

function cmd_status() {
	local json
	json=$(aws ec2 describe-instances \
		--filters "Name=tag:knfsd-fio,Values=captain,client" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
		--query 'Reservations[].Instances[]' \
		--output json 2> /dev/null) || true
	if [[ -z "${json}" || "${json}" == "[]" || "${json}" == "null" ]]; then
		echo -e "${SHELL_BLUE}No knfsd-fio-* instances found.${SHELL_DEFAULT}"
		return 0
	fi
	printf "%-24s %-22s %-16s %-16s %-16s %s\n" "Name" "InstanceId" "Type" "State" "FIO:Status" "PrivateIp"
	echo "${json}" | jq -r '.[] | [
		((.Tags[]? | select(.Key=="Name") | .Value) // "" | if . == "" then "-" else . end),
		.InstanceId,
		.InstanceType,
		.State.Name,
		((.Tags[]? | select(.Key=="knfsd-file-cache:status") | .Value) // "" | if . == "" then "-" else . end),
		(.PrivateIpAddress // "-")
	] | @tsv' | sort -t$'\t' -k1,1V | while read -r name id type state knfsd_status ip; do
		local color
		case "${state}" in
			running) color="${SHELL_GREEN}" ;;
			pending) color="${SHELL_BLUE}" ;;
			*) color="${SHELL_RED}" ;;
		esac
		printf "%-24s %-22s %-16s ${color}%-16s${SHELL_DEFAULT} %-16s %s\n" \
			"${name}" "${id}" "${type}" "${state}" "${knfsd_status}" "${ip}"
	done
}

function cmd_destroy() {
	local ids
	ids=$(aws ec2 describe-instances \
		--filters "Name=tag:knfsd-fio,Values=captain,client" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
		--query 'Reservations[].Instances[].InstanceId' --output text 2> /dev/null)
	if [[ -z "${ids}" ]]; then
		echo -e "${SHELL_BLUE}No knfsd-fio-* instances found.${SHELL_DEFAULT}"
		return 0
	fi
	aws ec2 delete-tags --resources ${ids} --tags "Key=Name" "Key=knfsd-file-cache:status"
	aws ec2 terminate-instances --instance-ids ${ids} > /dev/null
	local id_count
	id_count=$(echo "${ids}" | wc -w)
	echo "Terminated (${id_count}):"
	for iid in ${ids}; do
		echo -e "  ${SHELL_RED}${iid}${SHELL_DEFAULT}"
	done
}

# main
case "${1:-}" in
	apply)
		shift
		parse_args "$@"
		cmd_apply
		;;
	scale)
		shift
		parse_args "$@"
		cmd_scale
		;;
	run)
		shift
		parse_args "$@"
		cmd_run
		;;
	status)
		cmd_status
		;;
	destroy)
		cmd_destroy
		;;
	help | -h | --help | "")
		usage
		exit 0
		;;
	*)
		echo -e "${SHELL_RED}ERROR: First argument must be a command: apply, scale, run, destroy, status, or help (got: ${1:-<empty>})${SHELL_DEFAULT}" >&2
		exit 1
		;;
esac
