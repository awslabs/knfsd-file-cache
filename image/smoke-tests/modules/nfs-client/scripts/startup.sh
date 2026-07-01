#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# NFS client startup script. Installs the NFS client tooling (nfs-common) used
# by the smoke-test "remote.test" binary to mount and compare the source NFS
# server against the KNFSD proxy. No NFS mounts are performed here; the Go
# driver mounts on demand using the hosts surfaced via instance tags.

set -o errexit
set -o pipefail
set -o nounset

export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

log() { echo "[nfs-client] $*"; }

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
		update_status "error: nfs-client startup failed (exit $${rc})"
	fi
}
trap on_exit EXIT

log "Installing aws-cli"
snap install aws-cli --classic

log "Installing nfs-common"
apt-get -y -q update
apt-get -y -q install -o=Dpkg::Use-Pty=0 nfs-common

log "nfs-client startup complete"
startup_complete=yes
update_status "ready"
