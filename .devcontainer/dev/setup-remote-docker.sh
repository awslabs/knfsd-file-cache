#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -eo pipefail

HOSTNAME="knfsd-dev-ec2"
USERNAME="ubuntu"

## disable unattended-upgrades.service
systemctl disable unattended-upgrades.service

## instance identity for self-tagging and the regional SSM agent download
REGION="$(cloud-init query region)"
INSTANCE_ID="$(cloud-init query instance_id)"

## install aws-cli
apt-get -o DPkg::Lock::Timeout=60 -y -q update
apt-get -o DPkg::Lock::Timeout=60 install -y -q unzip
curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --retry-max-time 300 --connect-timeout 30 --max-time 600 \
	-o /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip"
unzip -q -d /tmp /tmp/awscliv2.zip
/tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
rm -rf /tmp/awscliv2.zip /tmp/aws

## replace the preinstalled snap amazon-ssm-agent with the official .deb
## from the regional S3 bucket ("latest" matches the snap "candidate" channel)
curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --retry-max-time 300 --connect-timeout 30 --max-time 600 \
	-o /tmp/amazon-ssm-agent.deb "https://s3.${REGION}.amazonaws.com/amazon-ssm-${REGION}/latest/debian_$(dpkg --print-architecture)/amazon-ssm-agent.deb"
timeout 300 snap wait system seed.loaded
snap remove --purge amazon-ssm-agent
dpkg -i /tmp/amazon-ssm-agent.deb
systemctl enable --now amazon-ssm-agent
rm -f /tmp/amazon-ssm-agent.deb

## update_status() sets the tag:"knfsd-file-cache:status" on this instance.
## @param (str) $1 status value (e.g. "ready", "error: ...")
update_status() {
	aws ec2 create-tags \
		--region "${REGION}" \
		--resources "${INSTANCE_ID}" \
		--tags "Key=knfsd-file-cache:status,Value=$1" 2> /dev/null || true
}

## On any unexpected exit before completion, record an error status so
## "remote.sh" fails fast instead of waiting for the full timeout.
startup_complete=no
on_exit() {
	local rc=$?
	if [[ $startup_complete != "yes" && $rc -ne 0 ]]; then
		update_status "error: setup-remote-docker failed (exit ${rc})"
	fi
}
trap on_exit EXIT

update_status "installing"

## setup docker apt repo
install -m 0755 -d /etc/apt/keyrings \
	&& curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
	&& chmod a+r /etc/apt/keyrings/docker.asc \
	&& echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

## install docker & cleanup apt pkgs
apt-get -y -q update && apt-get -y -q upgrade \
	&& apt-get -y -q install \
		acl \
		iputils-ping \
		jq \
		locales \
		traceroute \
		containerd.io \
		docker-buildx-plugin \
		docker-ce \
		docker-ce-cli \
		docker-compose-plugin \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

## configure en_US.UTF-8 locale
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen \
	&& update-locale LC_ALL=C.UTF-8 LANG=en_US.UTF-8

## grant sudo rights, symlink python3
echo rm -f /etc/sudoers.d/90-cloud-init-users \
	&& echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL >> /etc/sudoers.d/${USERNAME} \
	&& chmod 0440 /etc/sudoers.d/${USERNAME} \
	&& ln -sf /usr/bin/python3 /usr/bin/python

## add aliases, silence motd/sudo messages
echo "alias cls='clear'" >> /home/${USERNAME}/.bashrc \
	&& touch "/home/${USERNAME}/.hushlogin"

## change hostname
hostnamectl set-hostname ${HOSTNAME}

## change permissions for docker
usermod -aG docker ${USERNAME}
setfacl --modify user:${USERNAME}:rw /var/run/docker.sock

## configure default logging driver for docker
mkdir -p /etc/docker \
	&& jq -n '{"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "5"}}' >> /etc/docker/daemon.json

## create git repo dir
mkdir -p /knfsd-file-cache && chown ${USERNAME}:${USERNAME} /knfsd-file-cache

## create empty ~/.aws directory
mkdir -p /home/${USERNAME}/.aws && chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.aws

## advertise readiness to "remote.sh"
startup_complete=yes
update_status "ready"
