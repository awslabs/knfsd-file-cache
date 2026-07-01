#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# requires systemd/init-system, run via remote-ssh on EC2 instance

set -o errexit
set -o pipefail

## set variables
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

ARCH=$(uname -m)

apt-get -y -q update
apt-get install -y rpcbind nfs-kernel-server

apt-get install -y -qq \
	libtirpc-dev libncurses-dev flex bison openssl libssl-dev dkms \
	libelf-dev libudev-dev libpci-dev libiberty-dev autoconf dwarves \
	build-essential libevent-dev libsqlite3-dev libblkid-dev \
	libmount-dev libwrap0-dev libkrb5-dev libldap2-dev libcap-dev \
	libkeyutils-dev libdevmapper-dev libxml2-dev cdbs debhelper ubuntu-dev-tools \
	gawk llvm pkg-config shellcheck bc libnl-3-dev libnl-genl-3-dev \
	libreadline-dev

cd /tmp
curl -o nfs-utils-2.8.5.tar.gz https://cdn.kernel.org/pub/linux/utils/nfs-utils/2.8.5/nfs-utils-2.8.5.tar.gz
tar xvf nfs-utils-2.8.5.tar.gz
cd /tmp/nfs-utils-2.8.5

./configure \
	--build=${ARCH}-linux-gnu \
	--prefix=/usr \
	--includedir="\${prefix}"/include \
	--mandir="\${prefix}"/share/man \
	--infodir="\${prefix}"/share/info \
	--sysconfdir=/etc \
	--localstatedir=/var \
	--disable-option-checking \
	--disable-silent-rules \
	--libdir="\${prefix}"/lib/${ARCH}-linux-gnu \
	--runstatedir=/run \
	--disable-maintainer-mode \
	--disable-dependency-tracking \
	--mandir="\${prefix}"/share/man \
	--enable-libmount-mount \
	--enable-junction \
	--enable-svcgss \
	--with-pluginpath=/usr/lib/${ARCH}-linux-gnu/libnfsidmap \
	--with-tcp-wrappers \
	--with-systemd \
	--disable-sbin-override

make && make install
chmod u+w,go+r /usr/sbin/mount.nfs
chown nobody:nogroup /var/lib/nfs

## add entry to /etc/exports file
mkdir -p /srv/nfs
echo "/srv/nfs  *(rw,sync,wdelay,no_root_squash,no_all_squash,no_subtree_check,sec=sys,secure,crossmnt,fsid=10)" >> /etc/exports

## cleanup
apt-get autoremove -y
apt-get clean -y
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/nfs-utils-*

systemctl daemon-reload
systemctl restart portmap nfs-kernel-server

echo "### NFS Mounts ###"
findmnt -ut nfs,nfs4

echo "### NFS Exports ###"
exportfs -s
