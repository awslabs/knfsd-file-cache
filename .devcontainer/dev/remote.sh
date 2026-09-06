#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## Remote-SSH EC2 VM/Docker host management script for knfsd developers

## USAGE:
## ./remote.sh help|-h|--help
## ./remote.sh create|new [<vm|docker>] [<amd64|arm64>] [<ami-id>] ($BUILDARCH if present, also sets the architecture for the EC2 host)
## ./remote.sh up|start
## ./remote.sh down|stop
## ./remote.sh size <INSTANCE_TYPE>
## ./remote.sh sync <push|pull> [<test>]
## ./remote.sh creds
## ./remote.sh delete|del|terminate

## PRIVATE SUBNET:
## The EC2 instance is reached via a tunnel, so no inbound SSH (TCP:22) rule is required.
## Select the tunnel type with the KNFSD_REMOTE_SSH_TUNNEL env var:
##   export KNFSD_REMOTE_SSH_TUNNEL=eice # EC2 Instance Connect Endpoint (default)
##   export KNFSD_REMOTE_SSH_TUNNEL=ssm # AWS SSM Session Manager
##
## EICE: optionally pin the endpoint (otherwise inferred from the instance's VPC):
##   export KNFSD_REMOTE_SSH_EICE_ID=<eice-id>
## AWS docs: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html
##
## SSM: requires the "session-manager-plugin" installed locally (and on the local OS
## running VS Code, as ~/.ssh/config is shared), the EC2 IAM instance profile to allow
## the AWS SSM agent actions, and AWS SSM reachability (NAT or the ssm, ssmmessages and
## ec2messages interface VPC endpoints).
## AWS docs: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

set -eo pipefail

# terminal colors
SHELL_RED='\033[0;31m'
SHELL_GREEN='\033[0;32m'
SHELL_DEFAULT='\033[0m'

VERSION="1.1.0-beta.3"

REMOTE_HOST="knfsd-dev-ec2" # ensure unique name in AWS account
KNFSD_GIT_REPO=/knfsd-file-cache
USERNAME="ubuntu"
# ssh settings
IDENTITY_FILE="~/.ssh/id_rsa"
SSH_CONFIG_FILE=~/.ssh/config
# tunnel used to reach the instance: eice (default) or ssm
TUNNEL="${KNFSD_REMOTE_SSH_TUNNEL:-eice}"
# ami-id settings
PRODUCT="server" # server, server-minimal or pro-server
RELEASE="26.04"
ARCH=${BUILDARCH:-"amd64"} # amd64 or arm64
VOL_TYPE="ebs-gp3"
# ec2 settings
USER_DATA_SCRIPT="setup-remote-vm.sh" # run as EC2 VM
INSTANCE_TYPE="c6i.2xlarge" # c5n.2xlarge (amd64), c6in.2xlarge (amd64) or c6gn.2xlarge (arm64)
# use smaller instance size to save cost when heavy go downloading/compiling not required
VOLUME_SIZE=30
# max seconds to wait for the instance to become ready (AWS SSM agent/user-data script)
WAIT_TIMEOUT="${KNFSD_REMOTE_SSH_WAIT_TIMEOUT:-600}"
# EC2 tag set by the user-data scripts to advertise readiness
STATUS_TAG_KEY="knfsd-file-cache:status"

function usage() {
	cat >&2 << EOT
Ensure AWS credentials/region are configured.

Commands:
	./remote.sh help|-h|--help
		Show this message
	./remote.sh
		Start the EC2 instance and add ssh-config (default)
	./remote.sh create|new [<vm|docker>] [<amd64|arm64>] [<ami-id>](optional)
		Create a new EC2 VM (default) instance.
		Required ENV VARs:
			KNFSD_REMOTE_SSH_IAM_PROFILE_NAME
				The name of the EC2 IAM instance profile
			KNFSD_REMOTE_SSH_KEYPAIR
				The name of the EC2 keypair
			KNFSD_REMOTE_SSH_SUBNET
				The ID of the EC2 subnet
			KNFSD_REMOTE_SSH_SG_ID
				The ID of the EC2 security group
		Optional ENV VARs:
			KNFSD_REMOTE_SSH_TUNNEL
				Tunnel: eice (default) or ssm (AWS SSM Session Manager)
			KNFSD_REMOTE_SSH_EICE_ID
				EC2 Instance Connect Endpoint ID (eice tunnel only)
			KNFSD_REMOTE_SSH_WAIT_TIMEOUT
				Max seconds to wait for the instance to become ready (default: 600)
		[<vm|docker>] vm (default) or docker (devcontainer) on EC2 host [optional]
		[<amd64|arm64>] amd64 (default) or arm64 on EC2 host [optional]
		[<ami-id>] AMI ID [optional] or query AWS SSM parameter for "Ubuntu $RELEASE $ARCH $VOL_TYPE" AMI ID (default)
		ENV VAR: BUILDARCH=<amd64|arm64> also sets the architecture for the EC2 host [optional]
		Arguments can be provided in any order
	./remote.sh up|start
		Start the EC2 instance and add ssh-config
	./remote.sh down|stop
		Stop the EC2 instance
	./remote.sh size <INSTANCE_TYPE>
		Modify the instance type of the EC2 instance
	./remote.sh sync <push|pull> [<test>]
		<push> code changes from local <devcontainer> to <remote-ssh>
		<pull> code changes from <remote-ssh> to local <devcontainer>
		<test> run dry-run only [optional]
	./remote.sh creds
		Copy local AWS config/creds to <remote-ssh>
	./remote.sh delete|del|terminate
		Delete the EC2 instance and remove ssh-config
EOT
}

function require() {
	if [[ -z ${!1:-} ]]; then
		echo >&2 -e "${SHELL_RED}ERROR: '${1}' env var missing${SHELL_DEFAULT}"
		return 1
	else
		return 0
	fi
}

# validate-tunnel checks KNFSD_REMOTE_SSH_TUNNEL is a supported value.
function validate-tunnel() {
	if [[ ${TUNNEL} != "eice" && ${TUNNEL} != "ssm" ]]; then
		echo >&2 -e "${SHELL_RED}ERROR: KNFSD_REMOTE_SSH_TUNNEL must be 'eice' or 'ssm' (got: ${TUNNEL})${SHELL_DEFAULT}"
		return 1
	fi
	if [[ ${TUNNEL} == "ssm" ]] && ! command -v session-manager-plugin > /dev/null 2>&1; then
		echo >&2 -e "${SHELL_RED}ERROR: 'session-manager-plugin' not found in PATH${SHELL_DEFAULT}"
		return 1
	fi
	return 0
}

function initialize() {
	local error=0
	require KNFSD_REMOTE_SSH_KEYPAIR || error=1
	require KNFSD_REMOTE_SSH_SUBNET || error=1
	require KNFSD_REMOTE_SSH_SG_ID || error=1
	validate-tunnel || error=1
	return "${error}"
}

# get-region resolves the AWS region, printing it to stdout.
# The ProxyCommand is written to ~/.ssh/config, which is shared with the local OS
# running VS Code, so the region must be pinned explicitly rather than inherited.
function get-region() {
	local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
	if [[ -z ${region} ]]; then
		region=$(aws configure get region) || region=""
	fi
	if [[ -z ${region} ]]; then
		echo >&2 -e "${SHELL_RED}ERROR: unable to determine AWS region${SHELL_DEFAULT}"
		return 1
	fi
	echo "${region}"
}

function get-instance-id() {
	INSTANCE_ID=$(aws ec2 describe-instances \
		--filters "Name=tag:Name,Values=${REMOTE_HOST}" \
		--output text \
		--query 'Reservations[].Instances[].[InstanceId]')
}

# wait-for-ssm-online polls AWS SSM until the instance's agent reports PingStatus
# "Online" (registered and reachable). Unlike EICE, an SSM tunnel cannot be opened
# until the agent has registered, which lags the "running" state.
function wait-for-ssm-online() {
	local deadline=$((SECONDS + WAIT_TIMEOUT))
	local ping_status=""
	echo "INFO: ${REMOTE_HOST}: waiting for AWS SSM agent to report Online..."
	while ((SECONDS < deadline)); do
		ping_status=$(aws ssm describe-instance-information \
			--filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
			--query 'InstanceInformationList[0].PingStatus' \
			--output text 2> /dev/null) || ping_status=""
		if [[ ${ping_status} == "Online" ]]; then
			echo -e "INFO: ${REMOTE_HOST}: AWS SSM agent ${SHELL_GREEN}Online${SHELL_DEFAULT}"
			return 0
		fi
		sleep 5
	done
	echo >&2 -e "${SHELL_RED}ERROR: timed out after ${WAIT_TIMEOUT}s waiting for AWS SSM agent to report Online${SHELL_DEFAULT}"
	return 1
}

# wait-for-ready-tag polls the "knfsd-file-cache:status" tag set by the user-data
# script, returning once it reports "ready" and failing fast on an "error" status.
function wait-for-ready-tag() {
	local deadline=$((SECONDS + WAIT_TIMEOUT))
	local status=""
	echo "INFO: ${REMOTE_HOST}: waiting for user-data script to complete..."
	while ((SECONDS < deadline)); do
		status=$(aws ec2 describe-tags \
			--filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=${STATUS_TAG_KEY}" \
			--query 'Tags[0].Value' \
			--output text 2> /dev/null) || status=""
		case "${status}" in
			ready)
				echo -e "INFO: ${REMOTE_HOST}: ${SHELL_GREEN}ready${SHELL_DEFAULT}"
				return 0
				;;
			error*)
				echo >&2 -e "${SHELL_RED}ERROR: ${REMOTE_HOST} reported a failure status: ${status}${SHELL_DEFAULT}"
				return 1
				;;
		esac
		sleep 5
	done
	echo >&2 -e "${SHELL_RED}ERROR: timed out after ${WAIT_TIMEOUT}s waiting for ${STATUS_TAG_KEY}=ready (last status: ${status:-none})${SHELL_DEFAULT}"
	return 1
}

function create-instance() {
	# check for missing env vars
	if ! initialize; then
		exit 1
	fi

	local image_type="vm" # default to vm
	local arch=""
	local ami_id_override=""

	# handle different numbers of arguments
	case "$#" in
		1) ;;
		2)
			# check if second argument is vm/docker, amd64/arm64, or ami-id
			if [[ $2 == "vm" || $2 == "docker" ]]; then
				image_type="$2"
			elif [[ $2 == "amd64" || $2 == "arm64" ]]; then
				arch="$2"
			elif [[ $2 =~ ^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$ ]]; then
				ami_id_override="$2"
			else
				echo -e "${SHELL_RED}ERROR: Invalid second argument. Must be [<vm/docker>], [<amd64/arm64>], or [<ami-id>]${SHELL_DEFAULT}"
				exit 1
			fi
			;;
		3)
			# handle three arguments - determine what combination we have
			# argument 2
			if [[ $2 == "vm" || $2 == "docker" ]]; then
				image_type="$2"
			elif [[ $2 == "amd64" || $2 == "arm64" ]]; then
				arch="$2"
			elif [[ $2 =~ ^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$ ]]; then
				ami_id_override="$2"
			else
				echo -e "${SHELL_RED}ERROR: Invalid second argument. Must be [<vm/docker>], [<amd64/arm64>], or [<ami-id>]${SHELL_DEFAULT}"
				exit 1
			fi

			# argument 3
			if [[ $3 == "vm" || $3 == "docker" ]]; then
				image_type="$3"
			elif [[ $3 == "amd64" || $3 == "arm64" ]]; then
				arch="$3"
			elif [[ $3 =~ ^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$ ]]; then
				ami_id_override="$3"
			else
				echo -e "${SHELL_RED}ERROR: Invalid third argument. Must be [<vm/docker>], [<amd64/arm64>], or [<ami-id>]${SHELL_DEFAULT}"
				exit 1
			fi
			;;
		4)
			# handle four arguments
			local args=("$2" "$3" "$4")

			for arg in "${args[@]}"; do
				if [[ $arg == "vm" || $arg == "docker" ]]; then
					image_type="$arg"
				elif [[ $arg == "amd64" || $arg == "arm64" ]]; then
					arch="$arg"
				elif [[ $arg =~ ^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$ ]]; then
					ami_id_override="$arg"
				else
					echo -e "${SHELL_RED}ERROR: Invalid argument '$arg'. Must be [<vm/docker>], [<amd64/arm64>], or [<ami-id>]${SHELL_DEFAULT}"
					exit 1
				fi
			done
			;;
		*)
			echo -e "${SHELL_RED}ERROR: usage: create|new [<vm|docker>] [<amd64|arm64>] [<ami-id>]${SHELL_DEFAULT}"
			exit 1
			;;
	esac

	# "docker" override settings
	if [ "$image_type" == "docker" ]; then
		# optimized user-data script for minimal setup/faster boot time
		USER_DATA_SCRIPT="setup-remote-docker.sh"
	fi

	# check instance exists
	get-instance-id
	if [[ -n ${INSTANCE_ID} ]]; then
		printf 'INFO: ec2 instance already exists: %s\n' "${INSTANCE_ID}"
		exit 0
	fi

	# if $ARCH provided at CLI, override default script value & $BUILDARCH if present
	if [ -n "$arch" ]; then
		ARCH="$arch"
	fi

	# determine AMI ID - use override if provided, otherwise get from SSM
	local ami_id
	if [ -n "$ami_id_override" ]; then
		ami_id="$ami_id_override"
	else
		# https://documentation.ubuntu.com/aws/en/latest/aws-how-to/instances/find-ubuntu-images
		ami_id=$(aws ssm get-parameter \
			--name "/aws/service/canonical/ubuntu/${PRODUCT}/${RELEASE}/stable/current/${ARCH}/hvm/${VOL_TYPE}/ami-id" \
			--query 'Parameter.Value' \
			--output text)
	fi

	# check ami-id is valid
	local ami_id_regex="^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$"
	if [[ ! ${ami_id} =~ ${ami_id_regex} ]]; then
		echo -e "${SHELL_RED}ERROR: invalid ami-id: ${ami_id}${SHELL_DEFAULT}"
		exit 1
	fi

	local root_device_name
	root_device_name=$(aws ec2 describe-images \
		--image-ids "${ami_id}" \
		--query 'Images[*].RootDeviceName' \
		--output text)

	# check root device name is valid
	local root_device_name_regex="^\/dev\/[a-z]{3,4}[0-9]?$"
	if [[ ! ${root_device_name} =~ ${root_device_name_regex} ]]; then
		echo -e "${SHELL_RED}ERROR: invalid root device name: ${root_device_name}${SHELL_DEFAULT}"
		exit 1
	fi

	# if arm64, use c6g.large instance type
	if [ "${ARCH}" == "arm64" ]; then
		INSTANCE_TYPE="c6gn.2xlarge"
	fi

	# launch ec2 instance
	INSTANCE_ID=$(aws ec2 run-instances \
		--image-id "${ami_id}" \
		--instance-type "${INSTANCE_TYPE}" \
		--key-name "${KNFSD_REMOTE_SSH_KEYPAIR}" \
		--subnet-id "${KNFSD_REMOTE_SSH_SUBNET}" \
		--security-group-ids "${KNFSD_REMOTE_SSH_SG_ID}" \
		--iam-instance-profile Name="${KNFSD_REMOTE_SSH_IAM_PROFILE_NAME}" \
		--block-device-mappings '[{"DeviceName":"'"$root_device_name"'","Ebs":{"VolumeSize":'"$VOLUME_SIZE"',"VolumeType":"gp3","Encrypted":true}}]' \
		--user-data file://"${USER_DATA_SCRIPT}" \
		--metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=2,InstanceMetadataTags=enabled" \
		--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${REMOTE_HOST}},{Key=knfsd-file-cache:version,Value=${VERSION}},{Key=knfsd-file-cache:status,Value=starting}]" \
		--query 'Instances[0].InstanceId' \
		--output text)

	# "docker" override msg
	local msg="EC2 VM"
	if [ "$image_type" == "docker" ]; then msg="EC2 DOCKER HOST"; fi
	echo -e "INFO: ${REMOTE_HOST}: ${SHELL_GREEN}${INSTANCE_ID}${SHELL_DEFAULT} created as: ${SHELL_GREEN}${msg}${SHELL_DEFAULT}"

	add-ssh-config

	# wait for the instance to finish provisioning before handing back to the user
	if [[ ${TUNNEL} == "ssm" ]]; then
		wait-for-ssm-online
	fi
	wait-for-ready-tag
}

function start-instance() {
	# check tunnel type is valid
	if ! validate-tunnel; then
		exit 1
	fi

	get-instance-id
	if [[ -z ${INSTANCE_ID} ]]; then
		echo -e "${SHELL_RED}ERROR: ec2 instance with Name=${REMOTE_HOST} not found${SHELL_DEFAULT}"
		exit 1
	fi

	# check if instance is already running
	local state
	state=$(aws ec2 describe-instances --instance-id "${INSTANCE_ID}" \
		--query 'Reservations[*].Instances[*].State.Name' --output text)
	if [ "$state" == "running" ] || [ "$state" == "pending" ]; then
		echo -e "INFO: ${REMOTE_HOST}: ${SHELL_GREEN}already running${SHELL_DEFAULT}"
		exit 0
	fi

	# start instance
	aws ec2 start-instances --instance-ids "${INSTANCE_ID}" > /dev/null
	echo -e "INFO: ${REMOTE_HOST}: ${SHELL_GREEN}started${SHELL_DEFAULT}"
	add-ssh-config

	# the user-data script only runs on first boot, so only the AWS SSM agent
	# registration needs waiting on here
	if [[ ${TUNNEL} == "ssm" ]]; then
		wait-for-ssm-online
	fi
}

function add-ssh-config() {
	# build the ProxyCommand for the selected tunnel type
	local proxy_cmd
	if [[ ${TUNNEL} == "ssm" ]]; then
		local region
		region=$(get-region) || exit 1
		# %h resolves to the instance-id (HostName) and %p to the port (22)
		proxy_cmd="aws ssm start-session --target %h"
		proxy_cmd="${proxy_cmd} --document-name AWS-StartSSHSession"
		proxy_cmd="${proxy_cmd} --parameters 'portNumber=%p'"
		proxy_cmd="${proxy_cmd} --region ${region}"
		if [[ -n ${AWS_PROFILE:-} ]]; then
			proxy_cmd="${proxy_cmd} --profile ${AWS_PROFILE}"
		fi
	else
		proxy_cmd="aws ec2-instance-connect open-tunnel --instance-id %h"
		if [[ -n ${KNFSD_REMOTE_SSH_EICE_ID:-} ]]; then
			proxy_cmd="${proxy_cmd} --instance-connect-endpoint-id ${KNFSD_REMOTE_SSH_EICE_ID}"
		fi
	fi

	# backup ~/.ssh/config file to config.bak
	cp ${SSH_CONFIG_FILE} ${SSH_CONFIG_FILE}.bak
	# remove any "Host ${REMOTE_HOST}" entries in ${SSH_CONFIG_FILE}
	sed -i -e 's/^Host/\n&/' ${SSH_CONFIG_FILE}
	sed -i -e '/^Host '"${REMOTE_HOST}"'$/,/^$/d;/^$/d' ${SSH_CONFIG_FILE}
	# echo in new lines to bottom of ${SSH_CONFIG_FILE}
	cat << EOT >> ${SSH_CONFIG_FILE}
Host ${REMOTE_HOST}
	User ${USERNAME}
	HostName ${INSTANCE_ID}
	IdentityFile ${IDENTITY_FILE}
	StrictHostKeyChecking no
	ForwardAgent yes
	IdentitiesOnly yes
	ConnectTimeout 30
	ServerAliveInterval 30
	ServerAliveCountMax 5
	ProxyCommand bash -c "${proxy_cmd}"
EOT
	echo "INFO: ssh config file: ${SSH_CONFIG_FILE}"
	echo -e "INFO: ssh config added: ${SHELL_GREEN}${REMOTE_HOST}${SHELL_DEFAULT} (tunnel: ${SHELL_GREEN}${TUNNEL}${SHELL_DEFAULT})"
}

function delete-ssh-config() {
	sed -i -e 's/^Host/\n&/' ${SSH_CONFIG_FILE}
	sed -i -e '/^Host '"${REMOTE_HOST}"'$/,/^$/d;/^$/d' ${SSH_CONFIG_FILE}
	echo "INFO: ssh config file: ${SSH_CONFIG_FILE}"
	echo -e "INFO: ssh config deleted: ${SHELL_RED}${REMOTE_HOST}${SHELL_DEFAULT}"
}

function modify-instance() {
	# check instance type specified
	if [ "$#" -ne 2 ]; then
		echo -e "${SHELL_RED}ERROR: instance type not specified${SHELL_DEFAULT}"
		exit 1
	fi

	local new_instance_type=$2
	# check if instance type is valid
	if ! echo "${new_instance_type}" | grep -qE '^[a-z][a-z0-9-]*\.(metal(-[0-9]+xl)?|[a-z0-9]+)$'; then
		echo -e "${SHELL_RED}ERROR: invalid instance type: ${new_instance_type}${SHELL_DEFAULT}"
		exit 1
	fi

	# check the new instance type exists in region
	local type_exists
	type_exists=$(aws ec2 describe-instance-type-offerings \
		--filters "Name=instance-type,Values=${new_instance_type}" \
		--output text --query 'InstanceTypeOfferings[*].InstanceType')
	if [ -z "${type_exists}" ]; then
		echo -e "${SHELL_RED}ERROR: ${new_instance_type} not available in this region${SHELL_DEFAULT}"
		exit 1
	fi

	# check instance exists
	get-instance-id
	if [[ -z ${INSTANCE_ID} ]]; then
		echo -e "${SHELL_RED}ERROR: ec2 instance with Name=${REMOTE_HOST} not found${SHELL_DEFAULT}"
		exit 1
	fi

	# check instance is stopped
	local state
	state=$(aws ec2 describe-instances --instance-id "${INSTANCE_ID}" \
		--query 'Reservations[*].Instances[*].State.Name' --output text)
	if [ "$state" != "stopped" ]; then
		echo "INFO: ${REMOTE_HOST}: is running! Use './remote.sh down' to stop instance"
		exit 0
	fi

	# modify instance type
	aws ec2 modify-instance-attribute --instance-id "${INSTANCE_ID}" --instance-type "${new_instance_type}" > /dev/null
	echo -e "INFO: ${REMOTE_HOST} size modified to: ${SHELL_GREEN}${new_instance_type}${SHELL_DEFAULT}"
}

function sync-repo() {
	# check for min 2 or max 3 arguments
	if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
		echo -e "${SHELL_RED}ERROR: usage: sync <push|pull> [<test>]${SHELL_DEFAULT}"
		exit 1
	fi

	# check for <push|pull> argument
	local cmd1=$2
	if [ ! "$cmd1" == "push" ] && [ ! "$cmd1" == "pull" ]; then
		echo -e "${SHELL_RED}ERROR: sync <push|pull> not specified. Typo?${SHELL_DEFAULT}"
		exit 1
	fi

	# validate <test> argument if provided
	local cmd2=""
	if [ "$#" -eq 3 ]; then
		cmd2=$3
		if [ ! "$cmd2" == "test" ]; then
			echo -e "${SHELL_RED}ERROR: sync <push|pull> <test> argument not valid. Typo?${SHELL_DEFAULT}"
			exit 1
		fi
	fi

	# check instance exists
	get-instance-id
	if [[ -z ${INSTANCE_ID} ]]; then
		echo -e "${SHELL_RED}ERROR: ec2 instance with Name=${REMOTE_HOST} not found${SHELL_DEFAULT}"
		exit 1
	fi

	# check instance is running
	local state
	state=$(aws ec2 describe-instances --instance-id "${INSTANCE_ID}" \
		--query 'Reservations[*].Instances[*].State.Name' --output text)
	if [ "$state" != "running" ]; then
		echo "INFO: ${REMOTE_HOST}: is not running! Use './remote.sh up' to start instance"
		exit 0
	fi

	cd ${KNFSD_GIT_REPO}
	if [ "$cmd1" == "push" ]; then
		if [ "$cmd2" == "test" ]; then
			rsync -rlznia --delete . "${USERNAME}@${REMOTE_HOST}:${KNFSD_GIT_REPO}" \
				| grep -Ev "sending incremental file list" | grep -Ev "^\." | awk '{print $2}'
		else
			rsync -hrlptzv --delete . "${USERNAME}@${REMOTE_HOST}:${KNFSD_GIT_REPO}"
		fi
	else
		if [ "$cmd2" == "test" ]; then
			rsync -rlznia --delete "${USERNAME}@${REMOTE_HOST}:${KNFSD_GIT_REPO}/" . \
				| grep -Ev "sending incremental file list" | grep -Ev "^\." | awk '{print $2}'
		else
			rsync -hrlptzv --delete "${USERNAME}@${REMOTE_HOST}:${KNFSD_GIT_REPO}/" .
		fi
	fi
}

function sync-creds() {
	# check instance exists
	get-instance-id
	if [[ -z ${INSTANCE_ID} ]]; then
		echo -e "${SHELL_RED}ERROR: ec2 instance with Name=${REMOTE_HOST} not found${SHELL_DEFAULT}"
		exit 1
	fi

	# check instance is running
	local state
	state=$(aws ec2 describe-instances --instance-id "${INSTANCE_ID}" \
		--query 'Reservations[*].Instances[*].State.Name' --output text)
	if [ "$state" != "running" ]; then
		echo "INFO: ${REMOTE_HOST}: is not running! Use './remote.sh up' to start instance"
		exit 0
	fi

	# copy local/devcontainer AWS creds to remote-ssh
	rsync -hlptzv "/home/${USERNAME}/.aws/config" "/home/${USERNAME}/.aws/credentials" \
		"${USERNAME}@${REMOTE_HOST}:/home/${USERNAME}/.aws/"

	echo "INFO: AWS creds/config synced to remote-ssh"
}

function stop-instance() {
	get-instance-id
	if [[ -z ${INSTANCE_ID} ]]; then
		echo -e "${SHELL_RED}ERROR: ec2 instance with Name=${REMOTE_HOST} not found${SHELL_DEFAULT}"
		exit 1
	fi

	aws ec2 stop-instances --instance-ids "${INSTANCE_ID}" > /dev/null
	echo -e "INFO: ${REMOTE_HOST}: ${SHELL_GREEN}stopped${SHELL_DEFAULT}"
}

function delete-instance() {
	get-instance-id
	if [[ -z ${INSTANCE_ID} ]]; then
		echo -e "${SHELL_RED}ERROR: ec2 instance with Name=${REMOTE_HOST} not found${SHELL_DEFAULT}"
		exit 1
	fi

	aws ec2 delete-tags --resources "${INSTANCE_ID}" \
		--tags "Key=Name" "Key=knfsd-file-cache:status" "Key=knfsd-file-cache:version" > /dev/null
	aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" > /dev/null
	echo -e "INFO: ${REMOTE_HOST}: ${SHELL_RED}${INSTANCE_ID}${SHELL_DEFAULT} deleted"
	delete-ssh-config
}

case "$1" in
	# By default, automatically start ec2 instance & add ssh-config
	# Shortcut for: ./remote.sh up|start
	"") start-instance ;;

	create | new) create-instance "$@" ;;

	up | start) start-instance ;;

	down | stop) stop-instance ;;

	size) modify-instance "$@" ;;

	sync) sync-repo "$@" ;;

	creds) sync-creds ;;

	delete | del | terminate) delete-instance ;;

	help | -h | --help) usage ;;

	*)
		printf 'Unknown command: "%s"\n\n' "$1"
		usage
		;;
esac
