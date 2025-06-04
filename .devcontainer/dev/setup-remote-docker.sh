#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

HOSTNAME="knfsd-dev-ec2"
USERNAME="ubuntu"

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

## silence sudo usage message, grant sudo rights, symlink python3
echo "Defaults !admin_flag" >> /etc/sudoers.d/disable_admin_file \
	&& rm -f /etc/sudoers.d/90-cloud-init-users \
	&& chmod 0440 /etc/sudoers.d/disable_admin_file \
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
