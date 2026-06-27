#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Source NFS server startup script. Renders the local NVMe instance store as
# an XFS filesystem mounted at /srv/nfs/files and exports it as /files via NFS
# (v3 and v4) to the VPC CIDR. Optionally applies tc traffic shaping.
#
# Configuration is delivered via EC2 instance tags (read through IMDSv2):
#   knfsd-file-cache:vpc-cidr   NFS export allowlist (e.g. "10.20.0.0/16")
#   knfsd-file-cache:delay      tc netem delay (e.g. "10ms"), empty disables
#   knfsd-file-cache:rate       tc netem rate (e.g. "100MBit"), empty disables

set -o errexit
set -o pipefail
set -o nounset

export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

log() { echo "[source-nfs] $*"; }

fatal() {
	echo "[source-nfs] FATAL: $*" >&2
	exit 1
}

# Instance identity for self-tagging the "knfsd-file-cache:status" tag
REGION="$(cloud-init query region)"
INSTANCE_ID="$(cloud-init query instance_id)"

# update_status() sets the tag:"knfsd-file-cache:status" on this instance.
# @param (str) $1 status value (e.g. "ready", "error: ...")
update_status() {
	aws ec2 create-tags \
		--region "$${REGION}" \
		--resources "$${INSTANCE_ID}" \
		--tags "Key=knfsd-file-cache:status,Value=$1" 2> /dev/null || true
}

# On any unexpected exit before completion, record an error status so the
# downstream readiness check fails fast instead of timing out.
startup_complete=no
on_exit() {
	local rc=$?
	if [[ $startup_complete != "yes" && $rc -ne 0 ]]; then
		update_status "error: source-nfs startup failed (exit $${rc})"
	fi
}
trap on_exit EXIT

log "Updating amazon-ssm-agent"
if ! snap debug seeding | grep -q "^seeded: *true$"; then
	log "Waiting for snap seeding to complete..."
	timeout 300 sh -c 'until snap debug seeding | grep -q "^seeded: *true$"; do sleep 5; done'
fi
snap stop amazon-ssm-agent
snap switch --channel=candidate amazon-ssm-agent
snap refresh amazon-ssm-agent
mkdir -p /etc/amazon/ssm
snap start amazon-ssm-agent

log "Installing aws-cli"
snap install aws-cli --classic

# Fetch a short-lived IMDSv2 token, then read instance tags through IMDS.
get_token() {
	curl -fsS -X PUT 'http://169.254.169.254/latest/api/token' \
		-H 'X-aws-ec2-metadata-token-ttl-seconds: 300'
}

get_tag() {
	local tag="$1"
	local token
	token="$(get_token)" || fatal "could not obtain IMDSv2 token"
	curl -fsS -H "X-aws-ec2-metadata-token: $${token}" \
		"http://169.254.169.254/latest/meta-data/tags/instance/$${tag}" 2> /dev/null || true
}

VPC_CIDR="$(get_tag 'knfsd-file-cache:vpc-cidr')"
DELAY="$(get_tag 'knfsd-file-cache:delay')"
RATE="$(get_tag 'knfsd-file-cache:rate')"

if [[ -z $VPC_CIDR ]]; then
	fatal "instance tag 'knfsd-file-cache:vpc-cidr' is required"
fi

log "Installing nfs-kernel-server, xfsprogs, iproute2"
apt-get -y -q update
apt-get -y -q install nfs-kernel-server xfsprogs iproute2

# Pin the NFSv3 ancillary RPC services (mountd, statd, lockd, sm-notify) to fixed
# ports so they can be allowed through the security group. Without this, rpcbind
# assigns these services random high ports and the proxy's NFSv3 mount (which
# contacts mountd via portmap) times out behind the firewall.
#
# The port assignments mirror the KNFSD proxy AMI (image/resources/etc/nfs.conf
# and image/resources/etc/modprobe.d/nfs.conf) for consistency, and must match
# the source NFS security group ingress range (20048-20055).
#
# mountd, statd and sm-notify honour /etc/nfs.conf; lockd (nlockmgr) is a kernel
# module and only honours its module/sysctl parameters, so it is pinned via
# modprobe.d below.
cat > /etc/nfs.conf.d/knfsd.conf << 'EOF'
[mountd]
port=20048

[statd]
port=20051
outgoing-port=20052

[lockd]
port=20053

[sm-notify]
outgoing-port=20054
EOF

cat > /etc/modprobe.d/nfs.conf << 'EOF'
options lockd nlm_tcpport=20050 nlm_udpport=20050
EOF

# Identify the largest local NVMe instance-store device (i3en/im4gn). Skip
# the EBS-backed root device (typically /dev/nvme0n1).
log "Locating instance-store NVMe device"
DEVICE=""
for dev in /dev/nvme[1-9]n1; do
	[[ -b $dev ]] || continue
	# instance-store NVMe shows as "Amazon EC2 NVMe Instance Storage"
	if nvme id-ctrl "$dev" -H 2> /dev/null | grep -q 'Instance Storage'; then
		DEVICE="$dev"
		break
	fi
done

if [[ -z $DEVICE ]]; then
	# Fallback: pick the first non-root NVMe device.
	ROOT_DEV="$(findmnt -no SOURCE / | sed 's/p[0-9]*$//')"
	for dev in /dev/nvme[1-9]n1; do
		[[ -b $dev ]] || continue
		if [[ $dev != "$ROOT_DEV" ]]; then
			DEVICE="$dev"
			break
		fi
	done
fi

if [[ -z $DEVICE ]]; then
	fatal "could not locate a non-root NVMe device for the NFS export"
fi
log "Using NVMe device $${DEVICE}"

# Format the device as XFS if not already done. Skip mid-run to support
# instance restarts on the same instance store (which is wiped on stop/start
# but persists across reboots).
if [[ "$(lsblk -no FSTYPE "$DEVICE")" != "xfs" ]]; then
	log "Formatting $${DEVICE} as XFS"
	mkfs.xfs -q -f -m reflink=0 "$DEVICE"
fi

MOUNT_PATH="/srv/nfs/files"
EXPORT_PATH="/files"
mkdir -p "$MOUNT_PATH"

if ! mountpoint -q "$MOUNT_PATH"; then
	log "Mounting $${DEVICE} at $${MOUNT_PATH}"
	mount "$DEVICE" "$MOUNT_PATH"
fi

# Bind /files to the mount so the NFS export path is stable.
mkdir -p "$EXPORT_PATH"
if ! mountpoint -q "$EXPORT_PATH"; then
	mount --bind "$MOUNT_PATH" "$EXPORT_PATH"
fi

EXPORT_OPTIONS="rw,sync,wdelay,no_root_squash,no_all_squash,no_subtree_check,sec=sys,secure,nohide"
log "Writing /etc/exports for $${VPC_CIDR}"
cat > /etc/exports << EOF
$${EXPORT_PATH} $${VPC_CIDR}($${EXPORT_OPTIONS})
EOF

systemctl enable nfs-kernel-server
systemctl restart nfs-kernel-server
exportfs -ra

# Optional traffic shaping. The primary ENI on Nitro instances is "ens5".
if [[ -n $DELAY || -n $RATE ]]; then
	IFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -n1)"
	[[ -n $IFACE ]] || fatal "could not determine default network interface for tc"

	tc_args=()
	[[ -n $DELAY ]] && tc_args+=(delay "$DELAY")
	[[ -n $RATE ]] && tc_args+=(rate "$RATE")

	log "Applying tc netem on $${IFACE}: $${tc_args[*]}"
	# Replace any existing qdisc to make the script idempotent on reboot.
	tc qdisc replace dev "$IFACE" root netem "$${tc_args[@]}"
fi

log "source-nfs startup complete"
startup_complete=yes
update_status "ready"
