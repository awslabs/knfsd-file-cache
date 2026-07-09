#!/usr/bin/env bash

# Copyright 2020 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o pipefail

# terminal colors
SHELL_YELLOW='\033[0;33m'
SHELL_DEFAULT='\033[0m'

# pinned versions
VERSION="1.1.0-alpha.29"
KERNEL="7.1.3"

# identify architecture
export ARCH=$(uname -m)
export ARCH_ALT=$(dpkg --print-architecture)
# kernel build naming (kernel/perf uses arm64, not aarch64)
export KERNEL_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "$ARCH")

# env vars
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export QUILT_PATCHES=debian/patches
export DEBFULLNAME=build DEBEMAIL=build@knfsd.localhost
export MAKE_VERBOSITY="-s" # quiet: warnings/errors/summary

# golang build cache
export GOCACHE="/mnt/build/go/.cache/go-build"
export GOMODCACHE="/mnt/build/go/pkg/mod"
export GOTMPDIR="/mnt/build/go/tmp"
export GOPROXY=https://proxy.golang.org,direct

# set the working directory to "/mnt/build"
cd "$(dirname "$0")"/../
PATCHES="$(pwd)/patches"

# cloud-init queries
REGION=$(cloud-init query region)
INSTANCE_ID=$(cloud-init query instance_id)

# whether to tag the build instance status (requires an IAM instance profile
# with the "ec2:CreateTags" permission); defaults to false if unset
TAG_BUILD_STATUS="${TAG_BUILD_STATUS:-false}"

# update_status() updates the tag:"knfsd-file-cache:status" of the instance
# @param (str) $1 message
function update_status() {
	[[ "${TAG_BUILD_STATUS}" == "true" ]] || return 0
	aws ec2 create-tags \
		--region "${REGION}" \
		--resources "${INSTANCE_ID}" \
		--tags "Key=knfsd-file-cache:status,Value=$1"
}

# format the terminal for a command output
function begin_command() {
	echo -e "\n${SHELL_YELLOW}---- RUNNING: $1${SHELL_DEFAULT}"
	update_status "build: $1"
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

# install aws-cli
function install_aws_cli() (
	echo -e "\n${SHELL_YELLOW}---- RUNNING: installing aws-cli${SHELL_DEFAULT}"
	COMMAND_START_TIME=$(date +%s)
	snap install aws-cli --classic
	complete_command
)

# disable unattended-upgrades.service
function disable_unattended_upgrades() {
	# Stop unattended-upgrades while building the image, otherwise apt-get might
	# fail because the apt cache is locked by the unattended-upgrade service.
	begin_command "disabling unattended-upgrades"
	systemctl disable unattended-upgrades.service
	complete_command
}

# git clone with retry, 10-50s delay between attempts
function git_clone() {
	local max_attempts=5
	local attempt
	local target="${!#}"
	if [[ "$target" == https://* ]] || [[ "$target" == git@* ]]; then
		target=$(basename "$target" .git)
	fi
	for attempt in $(seq 1 $max_attempts); do
		if git clone "$@"; then
			return 0
		fi
		echo "git clone failed (attempt $attempt/$max_attempts), retrying in ${attempt}0s..."
		rm -rf "$target"
		sleep $((attempt * 10))
	done
	echo "git clone failed after $max_attempts attempts"
	return 1
}

# snap refresh with retry, 10-50s delay between attempts
snap_refresh() {
	local max_attempts=5
	local attempt
	for attempt in $(seq 1 $max_attempts); do
		if snap refresh "$@"; then
			return 0
		fi
		echo "snap refresh failed (attempt $attempt/$max_attempts), retrying in ${attempt}0s..."
		sleep $((attempt * 10))
	done
	echo "snap refresh failed after $max_attempts attempts"
	return 1
}

# update amazon-ssm-agent
function update_amazon_ssm_agent() (
	begin_command "updating amazon-ssm-agent"

	# wait up to 5 mins for snap seeding to complete before proceeding
	if ! snap debug seeding | grep -q "^seeded: *true$"; then
		echo "Waiting for snap seeding to complete..."
		timeout 300 sh -c 'until snap debug seeding | grep -q "^seeded: *true$"; do sleep 5; done'
	fi

	snap stop amazon-ssm-agent
	snap switch --channel=candidate amazon-ssm-agent
	snap_refresh amazon-ssm-agent
	mkdir -p /etc/amazon/ssm
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
	begin_command "updating apt repositories"
	wait_for_apt_lock
	apt-get -o DPkg::Lock::Timeout=60 -y -qq update
	complete_command
)

# install packages
function install_packages() (
	begin_command "installing packages"
	apt-get -o DPkg::Lock::Timeout=60 install -y -qq rpcbind nfs-kernel-server fio stress-ng
	systemctl disable nfs-kernel-server
	systemctl disable nfs-idmapd.service
	complete_command
)

# install dependencies
function install_build_dependencies() (
	begin_command "installing build dependencies"
	apt-get -o DPkg::Lock::Timeout=60 install -y -qq \
		libtirpc-dev libncurses-dev flex bison openssl libssl-dev dkms \
		libelf-dev libudev-dev libpci-dev libiberty-dev autoconf dwarves \
		build-essential libevent-dev libsqlite3-dev libblkid-dev \
		libmount-dev libwrap0-dev libkrb5-dev libldap2-dev libcap-dev \
		libkeyutils-dev libdevmapper-dev libxml2-dev cdbs debhelper ubuntu-dev-tools \
		gawk llvm pkg-config shellcheck bc libnl-3-dev libnl-genl-3-dev \
		libreadline-dev libdw-dev libslang2-dev libnuma-dev libtraceevent-dev \
		python3-dev python-is-python3 binutils perl gettext cmake wget
	complete_command
)

# build and install mdadm from source
function install_mdadm() (
	begin_command "installing mdadm"
	# https://github.com/md-raid-utilities/mdadm
	git_clone --depth 1 --branch mdadm-4.6 https://github.com/md-raid-utilities/mdadm.git mdadm
	cd mdadm
	make ${MAKE_VERBOSITY}
	make install BINDIR=/usr/sbin
	complete_command
)

# build and install cachefilesd with patches
function install_cachefilesd() (
	begin_command "installing cachefilesd"

	pull-lp-source cachefilesd 0.10.10-0.6ubuntu1
	cd cachefilesd-0.10.10/
	mkdir -p debian/patches

	quilt import "${PATCHES}"/cachefilesd/*.patch
	quilt push -a

	debchange --local +knfsd "Applying custom patches"
	debuild -i -uc -us -b

	cd ..
	apt-get install -y \
		./cachefilesd_0.10.10-0.6ubuntu1+knfsd1_${ARCH_ALT}.deb \
		./cachefilesd-dbgsym_0.10.10-0.6ubuntu1+knfsd1_${ARCH_ALT}.ddeb

	systemctl disable cachefilesd
	echo "RUN=yes" >> /etc/default/cachefilesd
	complete_command
)

# download nfs-utils from source
function download_nfs-utils() (
	begin_command "downloading nfs-utils"
	# https://git.linux-nfs.org/?p=steved/nfs-utils.git;a=summary
	# Need nfs-utils >2.6.3 to support the new reexport features and fsidd service.
	# Resolute Raccoon (Ubuntu 26.04) has nfs-common 2.8.5
	curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --retry-max-time 300 --connect-timeout 30 --max-time 600 \
		-o nfs-utils.tar.gz https://cdn.kernel.org/pub/linux/utils/nfs-utils/2.8.5/nfs-utils-2.8.5.tar.gz
	tar xf nfs-utils.tar.gz
	complete_command
)

# build and install nfs-utils from source
function build_install_nfs-utils() (
	begin_command "installing nfs-utils"
	cd nfs-utils-2.8.5
	# https://launchpad.net/ubuntu/+source/nfs-utils
	# Using build options for nfs-utils 1:2.8.2-2ubuntu1 amd64.
	# https://launchpad.net/ubuntu/+source/nfs-utils/1:2.8.2-2ubuntu1/+build/30327487
	./configure \
		--quiet \
		--build=${ARCH}-linux-gnu \
		--prefix=/usr \
		--includedir="\${prefix}"/include \
		--mandir="\${prefix}"/share/man \
		--infodir="\${prefix}"/share/info \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-option-checking \
		--enable-silent-rules \
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
	make ${MAKE_VERBOSITY} V=0 -j "${nproc}"

	# Install directly using make.
	# Normally this isn't recommended as it will likely conflict with apt-get
	# but in this case it doesn't matter. When updating packages we'll just
	# build a new image from scratch.
	make install V=0 -j "${nproc}"

	chmod u+w,go+r /usr/sbin/mount.nfs
	chown nobody:nogroup /var/lib/nfs
	complete_command
)

# configure serial console for rescue
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-serial-console-prerequisites.html
function configure_serial_console() (
	begin_command "configuring serial console"
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
	update-grub
	complete_command
)

# limit CPU idle C-states to C1 via GRUB boot parameters to reduce
# interrupt/wake-up latency. Ignored on Graviton & EC2 instance
# sizes that do not expose C-state control.
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/processor_state_control.html
function configure_cpu_power_states() (
	begin_command "configuring CPU power states"
	cat > /etc/default/grub.d/60-cpu-power-states.cfg << 'EOF'
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX intel_idle.max_cstate=1 processor.max_cstate=1"
EOF
	update-grub
	complete_command
)

# install amazon-ec2-net-utils
function install_amazon_ec2_net_utils() (
	begin_command "installing amazon-ec2-net-utils"
	# always use 'git clone' to ensure .gitattributes is ignored (removes debian/ directory from build image)
	git_clone --depth 1 --branch v2.7.3 https://github.com/amazonlinux/amazon-ec2-net-utils.git amazon-ec2-net-utils
	cd amazon-ec2-net-utils
	# edit systemd global @timer settings, execute every 30s, after initial 30s delay, with jitter of 5s
	# Ubuntu 26.04 uses systemd v259: https://www.freedesktop.org/software/systemd/man/259/systemd.timer.html
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
	begin_command "installing cloudwatch agent"
	cd cloudwatch-agent
	curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --retry-max-time 300 --connect-timeout 30 --max-time 600 \
		-o amazon-cloudwatch-agent.deb https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/${ARCH_ALT}/latest/amazon-cloudwatch-agent.deb
	dpkg -i -E amazon-cloudwatch-agent.deb
	systemctl disable amazon-cloudwatch-agent
	cp amazon-cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
	complete_command
)

# install golang
function install_golang() (
	begin_command "installing golang"
	curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --retry-max-time 300 --connect-timeout 30 --max-time 600 \
		-o go.tar.gz https://dl.google.com/go/go1.26.5.linux-${ARCH_ALT}.tar.gz
	rm -rf /usr/local/go
	tar -C /usr/local -xzf go.tar.gz
	mkdir -p "$GOCACHE" "$GOMODCACHE" "$GOTMPDIR"
	complete_command
)

# install the knfsd-fsidd service
function install_fsidd_service() (
	begin_command "installing knfsd-fsidd service"
	cd knfsd-fsidd
	go build -o /usr/local/sbin/knfsd-fsidd -ldflags "-X main.version=${VERSION}"
	complete_command
)

# install the http knfsd-agent
function install_knfsd_agent() (
	begin_command "installing knfsd-agent"
	cd knfsd-agent
	go build -o /usr/local/bin/knfsd-agent -ldflags "-X main.version=${VERSION}"
	cp knfsd-logrotate.conf /etc/logrotate.d/
	cp knfsd-agent.service /etc/systemd/system/
	complete_command
)

# install the custom Open-Telemetry KNFSD metrics agent
function install_knfsd_metrics_agent() (
	begin_command "installing knfsd-metrics-agent"
	cd knfsd-metrics-agent
	go build -o /usr/local/bin/knfsd-metrics-agent -ldflags "-X main.version=${VERSION}"
	mkdir -p /etc/knfsd-metrics-agent
	cp config/*.yaml /etc/knfsd-metrics-agent/
	cp systemd/proxy.service /etc/systemd/system/knfsd-metrics-agent.service
	complete_command
)

# install the agent that filters NFS exports
function install_filter_exports() (
	begin_command "installing filter-exports"
	cd filter-exports
	go test ./...
	go build -o /usr/local/bin/filter-exports -ldflags "-X main.version=${VERSION}"
	complete_command
)

# install the NetApp exports detection service
function install_netapp_exports() (
	begin_command "installing netapp-exports"
	cd netapp-exports
	go run internal/testcert/gen_certs.go > internal/testcert/testcert.go
	go test ./...
	go build -o /usr/local/bin/netapp-exports -ldflags "-X main.version=${VERSION}"
	complete_command
)

# install the proxy startup script
function install_proxy_startup() (
	begin_command "installing proxy-startup"
	install -m 0755 startup/proxy-startup.sh /usr/local/sbin/proxy-startup.sh
	complete_command
)

# download kernel source
function download_kernel() (
	begin_command "downloading kernel: ${KERNEL}"
	curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --retry-max-time 300 --connect-timeout 30 --max-time 600 \
		-o linux-${KERNEL}.tar.gz https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${KERNEL}.tar.gz
	tar -xf linux-${KERNEL}.tar.gz
	complete_command
)

# configure and compile kernel
function build_kernel() (
	begin_command "compiling kernel: ${KERNEL}-knfsd"
	cd linux-${KERNEL}

	# copy running kernel config as base
	cp /boot/config-"$(uname -r)" .config

	# apply custom patches using quilt
	# uses global QUILT_PATCHES=debian/patches set at top of script
	mkdir -p debian/patches
	kernel_patches=("${PATCHES}"/kernel/*.patch)
	# skip if "patches/kernel" directory empty
	if [[ -e "${kernel_patches[0]}" ]]; then
		quilt import "${kernel_patches[@]}"
		quilt push -a
	fi

	# disable keys that reference non-existent Ubuntu cert files
	scripts/config --disable CONFIG_SYSTEM_TRUSTED_KEYS
	scripts/config --disable CONFIG_SYSTEM_REVOCATION_KEYS

	# disable debug info to reduce build time and disk space
	scripts/config --disable CONFIG_DEBUG_INFO
	scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
	scripts/config --disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT

	# remove irrelevant options
	scripts/config --disable CONFIG_ANDROID_BINDER_IPC
	scripts/config --disable CONFIG_ANDROID_BINDERFS
	scripts/config --disable CONFIG_MULTIPLEXER
	scripts/config --disable CONFIG_DRM
	scripts/config --disable CONFIG_AGP
	scripts/config --disable CONFIG_SOUND
	scripts/config --disable CONFIG_SND
	scripts/config --disable CONFIG_MEDIA_SUPPORT
	scripts/config --disable CONFIG_WLAN
	scripts/config --disable CONFIG_WIRELESS
	scripts/config --disable CONFIG_BT
	scripts/config --disable CONFIG_IIO
	scripts/config --disable CONFIG_USB_SERIAL
	scripts/config --disable CONFIG_INPUT_JOYSTICK
	scripts/config --disable CONFIG_INPUT_TABLET
	scripts/config --disable CONFIG_INPUT_TOUCHSCREEN
	scripts/config --disable CONFIG_GAMEPORT
	scripts/config --disable CONFIG_PARPORT
	scripts/config --disable CONFIG_PCMCIA

	# ensure ENA driver is built as a module, so it can be upgraded in custom kernel
	scripts/config --module CONFIG_ENA_ETHERNET
	scripts/config --enable CONFIG_NFSD
	scripts/config --enable CONFIG_NFSD_V4
	scripts/config --module CONFIG_NFS_FS
	scripts/config --enable CONFIG_NFS_V4
	scripts/config --enable CONFIG_NFS_FSCACHE
	scripts/config --enable CONFIG_FSCACHE
	scripts/config --module CONFIG_CACHEFILES
	scripts/config --enable CONFIG_BLK_DEV_NVME
	scripts/config --enable CONFIG_BLK_DEV_MD
	scripts/config --enable CONFIG_EXT4_FS
	scripts/config --enable CONFIG_XFS_FS
	scripts/config --enable CONFIG_OVERLAY_FS

	# raise stack frame-size warning threshold to reduce build log noise
	scripts/config --set-val CONFIG_FRAME_WARN 2048

	# set local version suffix (visible in uname -r)
	scripts/config --set-str CONFIG_LOCALVERSION "-knfsd"

	# update config with defaults for new options
	ARCH="${KERNEL_ARCH}" make ${MAKE_VERBOSITY} olddefconfig

	# build binary debian packages
	local nproc
	nproc=$(nproc)
	ARCH="${KERNEL_ARCH}" make ${MAKE_VERBOSITY} -j "${nproc}" bindeb-pkg

	complete_command
)

# install custom kernel
function install_kernel() (
	begin_command "installing kernel: ${KERNEL}-knfsd"
	cd linux-${KERNEL}/..

	# debug disk usage
	# echo "Disk usage (/mnt/build): $(df -h /mnt/build | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"

	# remove old kernel packages
	apt-get purge -yq linux-image-aws linux-headers-aws linux-aws 2> /dev/null || true
	DEBIAN_FRONTEND=noninteractive apt-get purge -yq \
		linux-image-"$(uname -r)" \
		linux-headers-"$(uname -r)" \
		linux-modules-"$(uname -r)" 2> /dev/null || true
	apt-get autoremove -y

	# install new kernel packages
	dpkg -i linux-image-*-knfsd*.deb
	dpkg -i linux-headers-*-knfsd*.deb
	dpkg -i linux-libc-dev*.deb

	complete_command
)

# compile perf
function build_install_perf() (
	begin_command "compiling perf"
	cd linux-${KERNEL}/tools/perf

	local nproc
	nproc=$(nproc)

	# perf make expects arm64/x86_64 (not aarch64); set ARCH in the environment
	ARCH="${KERNEL_ARCH}" make ${MAKE_VERBOSITY} -j "${nproc}" prefix=/usr
	ARCH="${KERNEL_ARCH}" make -j "${nproc}" prefix=/usr/local install
	complete_command
)

# copy various configuration files
function copy_config() (
	begin_command "copying config"
	chown --recursive root:root etc
	chmod --recursive u=rwX,go=rX etc
	cp --recursive ./etc /
	mkdir -p /srv/nfs
	complete_command
)

# run build steps
install_aws_cli
disable_unattended_upgrades
update_amazon_ssm_agent
apt_update
install_packages
install_build_dependencies
install_mdadm
install_cachefilesd
download_nfs-utils
build_install_nfs-utils
configure_serial_console
configure_cpu_power_states
install_amazon_ec2_net_utils
install_cloudwatch_agent
install_golang
export PATH=$PATH:/usr/local/go/bin
install_fsidd_service
install_knfsd_agent
install_knfsd_metrics_agent
install_filter_exports
install_netapp_exports
install_proxy_startup
download_kernel
build_kernel
install_kernel
build_install_perf
copy_config

update_status "running: rebooting"

echo -e "\n${SHELL_YELLOW}---- SUCCESS: Finished build image script. Reboot(ing) for new kernel to take effect${SHELL_DEFAULT}"
