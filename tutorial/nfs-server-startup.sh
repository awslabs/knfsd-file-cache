#!/usr/bin/env bash

# Copyright 2021 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Create a very simple NFS server to act as the source NFS server for the proxy.
# This script is designed to run on an AWS EC2 m5.xlarge instance using the
# root/boot EBS volume for NFS exports.

# exit immediately if a command exits with a non-zero status
set -o errexit
set -o pipefail
shopt -s lastpipe

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

# install NFS kernel server and portmap
echo "Installing NFS kernel server and portmap..."
apt-get install -y nfs-kernel-server portmap
echo "DONE with software install"

# prep server by making and exporting a directory and example file
echo "Preparing example file and directory exports on root volume..."
mkdir -p /data
dd if=/dev/zero of=/data/test.data count=10240 bs=1048576
chmod a+rw -R /data
exportfs :/data -o rw,sync,no_subtree_check,fsid=10

ip=$(cloud-init query ds.meta-data.local-ipv4)

echo
echo "SUCCESS: Your NFS server is now exporting a 10 GB example file at $ip:/data/test.data"
