#!/usr/bin/env bash

# Copyright 2020 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o pipefail

# terminal colors
SHELL_YELLOW='\033[0;33m'
SHELL_DEFAULT='\033[0m'

VERSION="1.1.0-alpha.16"

# identify the architecture
export ARCH=$(uname -m)

# set the architecture alternative for tools that use uname-style naming
if [ "$ARCH" = "x86_64" ]; then
	export ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
	export ARCH_ALT="arm64"
fi

# env vars
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export QUILT_PATCHES=debian/patches
export NAME=build EMAIL=build
# golang build cache
export GOCACHE="/mnt/build/go/.cache/go-build"
export GOMODCACHE="/mnt/build/go/pkg/mod"
export GOPROXY=https://proxy.golang.org,direct

# set the working directory to "/mnt/build"
cd "$(dirname "$0")"/../
PATCHES="$(pwd)/patches"

# format the terminal for a command output
function begin_command() {
	echo -e "\n${SHELL_YELLOW}---- RUNNING: $1${SHELL_DEFAULT}"
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

# disable unattended-upgrades.service
function disable_unattended_upgrades() {
	# Stop unattended-upgrades while building the image, otherwise apt-get might
	# fail because the apt cache is locked by the unattended-upgrade service.
	#
	# Bug in current (6.11.0) HWE kernel can cause a kernel panic when the
	# nfs-server.service is restarted. Unattended upgrades can restart this
	# service if upgrading the NFS packages (or libraries NFS depends on).
	#
	# To avoid this issue, disabling unattended-upgrades.service.
	begin_command "Disabling unattended-upgrades.service"
	systemctl disable unattended-upgrades.service
	complete_command
}

# update amazon-ssm-agent
function update_amazon_ssm_agent() (
	begin_command "Updating amazon-ssm-agent"

	# wait up to 5 mins for snap seeding to complete before proceeding
	if ! snap debug seeding | grep -q "^seeded: *true$"; then
		echo "Waiting for snap seeding to complete..."
		timeout 300 sh -c 'until snap debug seeding | grep -q "^seeded: *true$"; do sleep 5; done'
	fi

	snap stop amazon-ssm-agent
	snap switch --channel=candidate amazon-ssm-agent
	snap refresh amazon-ssm-agent
	snap start amazon-ssm-agent
	complete_command
)

# wait for apt lists lock to be released
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1069167
wait_for_apt_lock() {
	local max_attempts=60
	local attempt=1
	local lock_file="/var/lib/apt/lists/lock"
	while [ -f "${lock_file}" ] && fuser "${lock_file}" > /dev/null 2>&1; do
		echo "Waiting for apt lists lock to be released... ($attempt/$max_attempts)"
		sleep 5
		attempt=$((attempt + 1))
		if [ $attempt -gt $max_attempts ]; then
			echo "Timed out waiting for apt lists lock after 5 minutes"
			return 1
		fi
	done
	return 0
}

# update apt repositories
function apt_update() (
	begin_command "Updating apt repositories"
	wait_for_apt_lock
	apt-get -o DPkg::Lock::Timeout=60 -y -q update
	complete_command
)

# install NFS packages
function install_nfs_packages() (
	begin_command "Installing rpcbind and nfs-kernel-server"
	apt-get -o DPkg::Lock::Timeout=60 install -y rpcbind nfs-kernel-server
	systemctl disable nfs-kernel-server
	systemctl disable nfs-idmapd.service
	complete_command
)

# install dependencies
function install_build_dependencies() (
	begin_command "Installing build dependencies"
	apt-get -o DPkg::Lock::Timeout=60 install -y -qq \
		libtirpc-dev libncurses-dev flex bison openssl libssl-dev dkms \
		libelf-dev libudev-dev libpci-dev libiberty-dev autoconf dwarves \
		build-essential libevent-dev libsqlite3-dev libblkid-dev \
		libmount-dev libwrap0-dev libkrb5-dev libldap2-dev libcap-dev \
		libkeyutils-dev libdevmapper-dev cdbs debhelper ubuntu-dev-tools \
		gawk llvm pkg-config shellcheck bc libnl-3-dev libnl-genl-3-dev \
		libreadline-dev
	complete_command
)

# build and install cachefilesd with patches
function install_cachefilesd() (
	begin_command "Building and installing cachefilesd"

	pull-lp-source cachefilesd 0.10.10-0.2ubuntu1
	cd cachefilesd-0.10.10/
	mkdir -p debian/patches

	quilt import "${PATCHES}"/cachefilesd/*.patch
	quilt push -a

	debchange --local +knfsd "Applying custom patches"
	debuild -i -uc -us -b

	cd ..
	apt-get install -y \
		./cachefilesd_0.10.10-0.2ubuntu1+knfsd1_${ARCH_ALT}.deb \
		./cachefilesd-dbgsym_0.10.10-0.2ubuntu1+knfsd1_${ARCH_ALT}.ddeb

	systemctl disable cachefilesd
	echo "RUN=yes" >> /etc/default/cachefilesd
	complete_command
)

# download nfs-utils from source
function download_nfs-utils() (
	begin_command "Downloading nfs-utils"
	# https://git.linux-nfs.org/?p=steved/nfs-utils.git;a=summary
	# Need nfs-utils >2.6.3 to support the new reexport features and fsidd service.
	# Jammy Jellyfish (Ubuntu 22.04) has nfs-common 2.6.1
	# Noble Numbat (Ubuntu 24.04) has nfs-common 2.6.4
	# Plucky Puffin (Ubuntu 25.04) has nfs-common 2.8.2
	curl -o nfs-utils-2.8.4.tar.gz https://mirrors.edge.kernel.org/pub/linux/utils/nfs-utils/2.8.4/nfs-utils-2.8.4.tar.gz
	tar xf nfs-utils-2.8.4.tar.gz
	complete_command
)

# build and install nfs-utils from source
function build_install_nfs-utils() (
	begin_command "Building and installing nfs-utils"
	cd nfs-utils-2.8.4
	# https://launchpad.net/ubuntu/+source/nfs-utils
	# Using build options for nfs-utils 1:2.8.2-2ubuntu1 amd64.
	# https://launchpad.net/ubuntu/+source/nfs-utils/1:2.8.2-2ubuntu1/+build/30327487
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

	local nproc
	nproc=$(("$(nproc)+1"))
	make -j "${nproc}"

	# Install directly using make.
	# Normally this isn't recommended as it will likely conflict with apt-get
	# but in this case it doesn't matter. When updating packages we'll just
	# build a new image from scratch.
	make install -j "${nproc}"

	chmod u+w,go+r /sbin/mount.nfs
	chown nobody:nogroup /var/lib/nfs
	complete_command
)

# configure serial console for rescue
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-serial-console-prerequisites.html
function configure_serial_console() (
	begin_command "Configuring serial console"
	local cfg_file
	cfg_file="/etc/default/grub.d/50-cloudimg-settings.cfg"
	# Set GRUB_TIMEOUT=1
	sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "${cfg_file}"
	# Add GRUB_TIMEOUT_STYLE=menu if it doesn't exist
	grep -q '^GRUB_TIMEOUT_STYLE=' "${cfg_file}" || echo 'GRUB_TIMEOUT_STYLE=menu' >> "${cfg_file}"
	# Add or update GRUB_TERMINAL="console serial"
	sed -i '/^GRUB_TERMINAL=/d' "${cfg_file}"
	echo 'GRUB_TERMINAL="console serial"' >> "${cfg_file}"
	# Remove GRUB_HIDDEN_TIMEOUT if it exists
	sed -i '/^GRUB_HIDDEN_TIMEOUT=/d' "${cfg_file}"
	# Add GRUB_SERIAL_COMMAND="serial --speed=115200"
	sed -i '/^GRUB_SERIAL_COMMAND=/d' "${cfg_file}"
	echo 'GRUB_SERIAL_COMMAND="serial --speed=115200"' >> "${cfg_file}"
	# Update GRUB configuration
	update-grub
	complete_command
)

# install aws-cli
function install_aws_cli() (
	begin_command "Installing aws-cli"
	mkdir -p aws-cli
	cd aws-cli
	curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip"
	unzip -q awscliv2.zip
	./aws/install
	complete_command
)

# install amazon-ec2-net-utils
function install_amazon_ec2_net_utils() (
	begin_command "Installing amazon-ec2-net-utils"
	# do not upgrade (March 2025) to v2.5.4+ as it breaks the refresh-policy-routes timer for secondary ips
	git clone --depth 1 --branch v2.5.3 https://github.com/amazonlinux/amazon-ec2-net-utils.git amazon-ec2-net-utils
	cd amazon-ec2-net-utils
	# edit systemd global @timer settings, execute every 30s, after initial 30s delay, with jitter of 5s
	# Ubuntu 24.04 uses systemd v255: https://www.freedesktop.org/software/systemd/man/255/systemd.timer.html
	rm -f systemd/system/refresh-policy-routes@.timer
	cat <<- EOF > systemd/system/refresh-policy-routes@.timer
		[Timer]
		OnActiveSec=30
		OnUnitInactiveSec=30
		RandomizedDelaySec=5
		AccuracySec=1s
	EOF
	dpkg-buildpackage -uc -us -b
	apt-get install -y ../amazon-ec2-net-utils*.deb
	complete_command
)

# install amazon cloudwatch agent
function install_cloudwatch_agent() (
	begin_command "Installing cloudwatch agent"
	cd cloudwatch-agent
	curl -sSO https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/${ARCH_ALT}/latest/amazon-cloudwatch-agent.deb
	dpkg -i -E amazon-cloudwatch-agent.deb
	systemctl disable amazon-cloudwatch-agent
	cp amazon-cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
	complete_command
)

# install rust
function install_rust() (
	begin_command "Installing rust"
	# https://forge.rust-lang.org/infra/other-installation-methods.html#standalone
	curl -sSO https://static.rust-lang.org/dist/rust-1.88.0-${ARCH}-unknown-linux-gnu.tar.xz
	tar xf rust-1.88.0-${ARCH}-unknown-linux-gnu.tar.xz
	cd rust-1.88.0-${ARCH}-unknown-linux-gnu
	./install.sh
	complete_command
)

# install amazon-efs-utils
function install_amazon_efs_utils() (
	begin_command "Installing amazon-efs-utils"
	git clone --depth 1 --branch v2.3.2 https://github.com/aws/efs-utils efs-utils
	cd efs-utils
	./build-deb.sh
	apt-get install -y ./build/amazon-efs-utils*deb
	complete_command
)

# install golang
function install_golang() (
	begin_command "Installing golang"
	curl -o go1.25.4.linux-${ARCH_ALT}.tar.gz https://dl.google.com/go/go1.25.4.linux-${ARCH_ALT}.tar.gz
	rm -rf /usr/local/go
	tar -C /usr/local -xzf go1.25.4.linux-${ARCH_ALT}.tar.gz
	mkdir -p "$GOCACHE" "$GOMODCACHE"
	complete_command
)

# install the knfsd-fsidd service
function install_fsidd_service() (
	begin_command "Installing knfsd-fsidd service"
	cd knfsd-fsidd
	go build -o /usr/local/sbin/knfsd-fsidd -ldflags "-X main.version=${VERSION}"
	complete_command
)

# install the http knfsd-agent
function install_knfsd_agent() (
	begin_command "Installing knfsd-agent"
	cd knfsd-agent
	go build -o /usr/local/bin/knfsd-agent -ldflags "-X main.version=${VERSION}"
	cp knfsd-logrotate.conf /etc/logrotate.d/
	cp knfsd-agent.service /etc/systemd/system/
	complete_command
)

# install the custom Open-Telemetry KNFSD metrics agent
function install_knfsd_metrics_agent() (
	begin_command "Installing knfsd-metrics-agent"
	cd knfsd-metrics-agent
	go build -o /usr/local/bin/knfsd-metrics-agent -ldflags "-X main.version=${VERSION}"
	mkdir -p /etc/knfsd-metrics-agent
	cp config/*.yaml /etc/knfsd-metrics-agent/
	cp systemd/proxy.service /etc/systemd/system/knfsd-metrics-agent.service
	complete_command
)

# install the agent that filters NFS exports
function install_filter_exports() (
	begin_command "Installing filter-exports"
	cd filter-exports
	go test ./...
	go build -o /usr/local/bin/filter-exports -ldflags "-X main.version=${VERSION}"
	complete_command
)

# install the NetApp exports detection service
function install_netapp_exports() (
	begin_command "Installing netapp-exports"
	cd netapp-exports
	go run internal/testcert/gen_certs.go > internal/testcert/testcert.go
	go test ./...
	go build -o /usr/local/bin/netapp-exports -ldflags "-X main.version=${VERSION}"
	complete_command
)

# update to latest Linux HWE kernel
function update_kernel() (
	begin_command "Updating kernel"
	# remove AWS-specific kernel packages and current running kernel
	local version
	version=$(uname -r)
	apt-get purge -yq linux-image-aws linux-headers-aws linux-aws
	DEBIAN_FRONTEND=noninteractive apt-get purge -yq linux-image-"${version}" linux-headers-"${version}" linux-modules-"${version}"
	apt-get autoremove -y
	# install Linux HWE kernel: pinned to known good version
	apt-get -o DPkg::Lock::Timeout=60 install -y linux-image-6.14.0-29-generic linux-headers-6.14.0-29-generic linux-modules-6.14.0-29-generic
	complete_command
)

# copy various configuration files
function copy_config() (
	begin_command "Copying config"
	chown --recursive root:root etc
	chmod --recursive 0644 etc
	cp --recursive ./etc /
	mkdir -p /srv/nfs
	# symlink python3 to python
	ln -sf /usr/bin/python3 /usr/bin/python
	complete_command
)

# run build steps
disable_unattended_upgrades
update_amazon_ssm_agent
apt_update
install_nfs_packages
install_build_dependencies
install_cachefilesd
download_nfs-utils
build_install_nfs-utils
configure_serial_console
install_aws_cli
install_amazon_ec2_net_utils
install_cloudwatch_agent
install_rust
export PATH=$PATH:/root/.cargo/bin
install_amazon_efs_utils
install_golang
export PATH=$PATH:/usr/local/go/bin
install_fsidd_service
install_knfsd_agent
install_knfsd_metrics_agent
install_filter_exports
install_netapp_exports
update_kernel
copy_config

echo -e "\n${SHELL_YELLOW}---- SUCCESS: Finished build image script. Reboot(ing) for new kernel to take effect${SHELL_DEFAULT}"
