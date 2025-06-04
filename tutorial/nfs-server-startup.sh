#!/bin/bash

# Copyright 2021 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Create a very simple NFS server to act as the source NFS server for the proxy.

# Install NFS kernel server and portmap
echo "Installing NFS kernel server and portmap..."
apt-get update
apt-get install -y nfs-kernel-server portmap
apt-get clean
rm -rf "/var/lib/apt/lists/*"
echo "DONE with software install"

# Prep Server by making and exporting a directory and example file
echo "Preparing example file and directory exports"
mkdir /data
dd if=/dev/zero of=/data/test.data count=10240 bs=1048576
chmod a+rw -R /data
exportfs :/data -o rw,sync,no_subtree_check,fsid=10

echo
echo "SUCCESS: Your NFS server is now exporting a 10 gig example file at nfs-server:/data/test.data"
echo -e "${SHELL_DEFAULT}"
