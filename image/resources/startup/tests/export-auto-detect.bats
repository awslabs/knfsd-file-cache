# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC2329
function setup() {
	bats_load_library bats-support
	bats_load_library bats-assert
	load ./common.bash
	load ../proxy-startup.sh

	# avoid AWS / status tagging from begin_command/complete_command
	function begin_command() { :; }
	function complete_command() { :; }
	function update_status() { :; }

	# neutralize filesystem + mount side effects (overridden per-test as needed)
	function mkdir() { :; }
	function sleep() { :; }
	function is_mounted() { return 1; } # nothing pre-mounted
	function filter_exports() { cat; } # bypass the filter-exports binary

	# add_nfs_export() inputs
	EXPORTS_FILE="${BATS_TEST_TMPDIR}/knfsd.exports"
	: > "${EXPORTS_FILE}"
	EXPORT_OPTIONS="rw,sync"
	EXPORT_CIDR="10.0.0.0/8"
	FSID_MODE="static"
	MOUNT_OPTIONS="vers=3"

	# used by the errexit-regression tests that re-source the script in a
	# fresh "bash -c" so that errexit is active in a non-ignored context
	export PROXY_STARTUP="${BATS_TEST_DIRNAME}/../proxy-startup.sh"
}

#
# mount_nfs_server() - now returns (does not exit) so callers decide fatality
#

@test "mount_nfs_server returns non-zero after 3 failed attempts " {
	function mount() { return 1; }

	run mount_nfs_server 10.0.0.1 /remote /remote
	assert_failure
	assert_output --partial "(Attempt 1/3)"
	assert_output --partial "(Attempt 3/3)"
	assert_equal "$(grep -c 'Attempt' <<< "$output")" 3
	refute_output --partial "(Attempt 4/3)"
}

@test "mount_nfs_server succeeds when a retry succeeds " {
	echo 0 > "${BATS_TEST_TMPDIR}/attempts"
	function mount() {
		local n
		n=$(< "${BATS_TEST_TMPDIR}/attempts")
		n=$((n + 1))
		echo "$n" > "${BATS_TEST_TMPDIR}/attempts"
		((n >= 3)) && return 0
		return 1
	}

	run mount_nfs_server 10.0.0.1 /remote /remote
	assert_success
	assert_output --partial "NFS mount succeeded"
}

@test "mount_nfs_server returns non-zero when local path is a symlink " {
	ln -s /tmp/target "${BATS_TEST_TMPDIR}/link"

	run mount_nfs_server 10.0.0.1 /remote "${BATS_TEST_TMPDIR}/link"
	assert_failure
	assert_output --partial "matches a symlink"
}

#
# reexport() - propagates the mount result and only exports on success
#

@test "reexport does not add an export when the mount fails " {
	function mount_nfs_server() { return 1; }

	run reexport 10.0.0.1 /remote /remote
	assert_failure

	run cat "${EXPORTS_FILE}"
	assert_output ""
}

@test "reexport adds an export when the mount succeeds " {
	function mount_nfs_server() { return 0; }

	run reexport 10.0.0.1 /remote /remote
	assert_success

	run cat "${EXPORTS_FILE}"
	assert_output --partial "/remote"
}

#
# export_auto_detect() - log-and-continue + zero-mount guard
#

# the pseudo-root "/" is advertised but unmountable.
function _showmount_unmountable_root() {
	cat <<- 'EOF'
		/ (everyone)
		/projects/a 10.0.0.0/8
		/projects/b 10.0.0.0/8
	EOF
}

# fail to mount the pseudo-root "/" (remote ends in ":/"), succeed otherwise
function _mount_skip_root() {
	local remote="${*: -2:1}"
	[[ "$remote" == *:/ ]] && return 1
	return 0
}

@test "export_auto_detect skips an unmountable export and continues " {
	function showmount() { _showmount_unmountable_root; }
	function mount() { _mount_skip_root "$@"; }
	# shellcheck disable=SC2030,SC2031
	export EXPORT_HOST_AUTO_DETECT="10.12.0.194"

	run export_auto_detect
	assert_success
	assert_output --partial "WARNING: skipping auto-detected export 10.12.0.194:/;"
	assert_output --partial "mounted=2"
	assert_output --partial "skipped=1"

	# the per-project exports are re-exported; the pseudo-root "/" is not
	run cat "${EXPORTS_FILE}"
	assert_output --partial "/projects/a"
	assert_output --partial "/projects/b"
	refute_line --regexp '^/ '
}

@test "export_auto_detect fails when zero exports mount " {
	function showmount() { _showmount_unmountable_root; }
	function mount() { return 1; }
	# shellcheck disable=SC2030,SC2031
	export EXPORT_HOST_AUTO_DETECT="10.12.0.194"

	run export_auto_detect
	assert_failure
	assert_equal "$status" 1
	assert_output --partial "mounted zero exports"
}

@test "export_auto_detect re-exports every export when all mount " {
	function showmount() { _showmount_unmountable_root; }
	function mount() { return 0; }
	# shellcheck disable=SC2030,SC2031
	export EXPORT_HOST_AUTO_DETECT="10.12.0.194"

	run export_auto_detect
	assert_success
	refute_output --partial "WARNING"
	refute_output --partial "ERROR"
	assert_output --partial "mounted=3"
	assert_output --partial "skipped=0"

	run cat "${EXPORTS_FILE}"
	assert_output --partial "/projects/a"
	assert_output --partial "/projects/b"
}

@test "export_auto_detect skips when EXPORT_HOST_AUTO_DETECT is empty " {
	# shellcheck disable=SC2030,SC2031
	export EXPORT_HOST_AUTO_DETECT=""

	run export_auto_detect
	assert_success
	assert_output --partial "Skipping..."

	run cat "${EXPORTS_FILE}"
	assert_output ""
}

#
# Regression: explicit (EXPORT_MAP) and NetApp auto-detect remain fatal.
#
# These paths must abort startup when a mount fails, which depends on the
# script's "set -o errexit". bats invokes test/helper functions in a context
# where errexit is ignored (and bash keeps ignoring it for any errexit set
# from within that context), so the call is re-run in a fresh "bash -c" where
# the sourced script's top-level "set -o errexit" applies normally. cloud-init
# is stubbed before sourcing so that the script's own errexit does not abort on
# the cloud-init metadata lookup at source time.
#

@test "export_map remains fatal on mount failure " {
	run bash -c '
		function cloud-init() { echo "test"; }
		source "${PROXY_STARTUP}"
		function begin_command() { :; }
		function complete_command() { :; }
		function is_mounted() { return 1; }
		function mkdir() { :; }
		function sleep() { :; }
		function mount() { return 1; }
		MOUNT_OPTIONS="vers=3"
		EXPORT_MAP="10.1.2.3;/a;/a"
		export_map
	'
	assert_failure
	assert_output --partial "Maximum attempts reached"
	refute_output --partial "Finished processing of NFS re-exports"
}

@test "export_netapp remains fatal on mount failure " {
	run bash -c '
		function cloud-init() { echo "test"; }
		source "${PROXY_STARTUP}"
		function begin_command() { :; }
		function complete_command() { :; }
		function is_mounted() { return 1; }
		function mkdir() { :; }
		function sleep() { :; }
		function mount() { return 1; }
		function filter_exports() { cat; }
		function netapp-exports() { echo "10.1.2.3 /a"; }
		MOUNT_OPTIONS="vers=3"
		ENABLE_NETAPP_AUTO_DETECT="true"
		export_netapp
	'
	assert_failure
	assert_output --partial "Maximum attempts reached"
	refute_output --partial "Finished processing of dynamically detected NetApp exports"
}
