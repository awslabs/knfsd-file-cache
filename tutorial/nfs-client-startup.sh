#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# exit immediately if a command exits with a non-zero status
set -o errexit
set -o pipefail
shopt -s lastpipe

# env vars
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive

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

# install NFS client packages
apt-get install -y nfs-common

# mount the NFS proxy
mkdir -p /data
mount -t nfs -o vers=3 "${NFS_PROXY}:/srv/nfs/data" /data
