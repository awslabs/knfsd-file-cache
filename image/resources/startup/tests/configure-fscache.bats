# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function setup() {
	bats_load_library bats-support
	bats_load_library bats-assert
	load ./common.bash
	load ../proxy-startup.sh

	MOUNT_POINT="${BATS_TEST_TMPDIR}/fscache"
	XFS_IO_LOG="${BATS_TEST_TMPDIR}/xfs_io"
	XFS_IO_STATE="${BATS_TEST_TMPDIR}/extsize_state"

	mkdir -p "${MOUNT_POINT}"
	: > "${XFS_IO_LOG}"
	echo 0 > "${XFS_IO_STATE}"
}

# Stub xfs_io. Supports the two forms the startup script uses:
#   xfs_io -c "extsize" <path>            query, prints "[<bytes>] <path>"
#   xfs_io -c "extsize <bytes>" <path>    set, records the invocation
# The queried value is held in XFS_IO_STATE so tests can simulate a filesystem
# that already carries a hint from a previous boot.
# shellcheck disable=SC2329
function xfs_io() {
	local cmd="" path=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-c)
				cmd="$2"
				shift 2
				;;
			*)
				path="$1"
				shift
				;;
		esac
	done

	printf '%s|%s\n' "${cmd}" "${path}" >> "${XFS_IO_LOG}"

	if [[ ${cmd} == "extsize" ]]; then
		printf '[%s] %s\n' "$(< "${XFS_IO_STATE}")" "${path}"
		return 0
	fi

	# set form: "extsize -D <bytes>", only the mount point updates the query
	# state so tests can assert idempotency across runs
	if [[ ${path} == "${MOUNT_POINT}" ]]; then
		echo "${cmd##* }" > "${XFS_IO_STATE}"
	fi
	return 0
}

# count how many times the hint was set (as opposed to queried)
function count_set_calls() {
	grep -c '^extsize -D [0-9]' "${XFS_IO_LOG}" || true
}

@test "get_fscache_extsize parses the hint value" {
	echo 4194304 > "${XFS_IO_STATE}"
	run get_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_output "4194304"
}

@test "get_fscache_extsize reports 0 when the hint is unset" {
	run get_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_output "0"
}

@test "get_fscache_extsize reports 0 when xfs_io fails" {
	# shellcheck disable=SC2329
	function xfs_io() { return 1; }
	run get_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_output "0"
}

@test "applies the hint on a fresh filesystem" {
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=8
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "Setting XFS extent size hint to: 8 MiB"
	assert_line --partial "Applying XFS extent size hint (0 -> 8388608 bytes)"
	grep -qF "extsize -D 8388608|${MOUNT_POINT}" "${XFS_IO_LOG}"
}

@test "uses a single recursive -D call rather than one per directory" {
	# -D recursively descends, modifying the hint on directories only, so the
	# mount point and every existing cachefilesd directory are covered at once.
	mkdir -p "${MOUNT_POINT}/cache/Infs,3.0,2/@c1/subdir" "${MOUNT_POINT}/graveyard"
	touch "${MOUNT_POINT}/cache/Infs,3.0,2/@c1/backing-file"

	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=8
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_equal "$(count_set_calls)" "1"
	grep -qF "extsize -D 8388608|${MOUNT_POINT}" "${XFS_IO_LOG}"
}

@test "does not use -R, which fails on files that already have extents" {
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=8
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	run grep -cE '^extsize -R' "${XFS_IO_LOG}"
	assert_output "0"
}

@test "converts MiB to bytes for each allowed value" {
	local mib bytes
	for mib in 4 8 16; do
		bytes=$((mib * 1024 * 1024))
		echo 0 > "${XFS_IO_STATE}"
		: > "${XFS_IO_LOG}"
		# shellcheck disable=SC2030,SC2031
		export CACHEFILESD_EXTSIZE="${mib}"
		run configure_fscache_extsize "${MOUNT_POINT}"
		assert_success
		grep -qF "extsize -D ${bytes}|${MOUNT_POINT}" "${XFS_IO_LOG}"
	done
}

# Guards the CACHEFILESD_EXTSIZE Terraform default. The variable permits only
# 0, 4, 8 and 16, so the conversion is pinned to a literal for the default of 8
# rather than recomputing it, to catch an accidental unit change.
@test "converts the default of 8 MiB to 8388608 bytes" {
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=8
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "Setting XFS extent size hint to: 8 MiB"
	grep -qF "extsize -D 8388608|${MOUNT_POINT}" "${XFS_IO_LOG}"
}

@test "rejects values outside the allowed set before calling xfs_io" {
	# The Terraform variable validation restricts this to 0, 4, 8 and 16, but a
	# hand-edited SSM parameter could hold anything. Non-numeric input must not
	# reach xfs_io.
	local bad
	for bad in "" "8m" "8 MiB" "-8" "abc"; do
		: > "${XFS_IO_LOG}"
		# shellcheck disable=SC2030,SC2031
		export CACHEFILESD_EXTSIZE="${bad}"
		run configure_fscache_extsize "${MOUNT_POINT}"
		assert_success
		assert_line --partial "is not set to a number"
		assert_equal "$(count_set_calls)" "0"
	done
}

@test "is a no-op when the hint already matches" {
	echo 8388608 > "${XFS_IO_STATE}"
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=8
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "already set to 8388608 bytes; skipping"
	assert_equal "$(count_set_calls)" "0"
}

@test "0 disables the hint and clears an existing value" {
	echo 8388608 > "${XFS_IO_STATE}"
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=0
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "CACHEFILESD_EXTSIZE is 0; XFS extent size hint disabled"
	grep -qF "extsize -D 0|${MOUNT_POINT}" "${XFS_IO_LOG}"
}

@test "0 is a no-op when the hint is already unset" {
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=0
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "already set to 0 bytes; skipping"
	assert_equal "$(count_set_calls)" "0"
}

@test "re-applies to existing cachefilesd directories when the value changes" {
	# simulate a cache populated under a previous hint value
	echo 4194304 > "${XFS_IO_STATE}"
	mkdir -p "${MOUNT_POINT}/cache/Infs,3.0,2/@c1" "${MOUNT_POINT}/graveyard"
	touch "${MOUNT_POINT}/cache/Infs,3.0,2/@c1/backing-file"

	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=8
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "Applying XFS extent size hint (4194304 -> 8388608 bytes)"
	assert_line --partial "Finished applying XFS extent size hint"
	grep -qF "extsize -D 8388608|${MOUNT_POINT}" "${XFS_IO_LOG}"
}

@test "warns and returns when the hint cannot be applied" {
	function xfs_io() {
		local cmd="$2"
		if [[ ${cmd} == "extsize" ]]; then
			printf '[0] %s\n' "$3"
			return 0
		fi
		return 1
	}

	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=8
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "WARNING: failed to set XFS extent size hint"
	refute_line --partial "Finished applying XFS extent size hint"
}

@test "skips when the parameter is empty" {
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE=""
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "is not set to a number"
	assert_equal "$(count_set_calls)" "0"
}

@test "skips when the parameter is not numeric" {
	# shellcheck disable=SC2030,SC2031
	export CACHEFILESD_EXTSIZE="8m"
	run configure_fscache_extsize "${MOUNT_POINT}"
	assert_success
	assert_line --partial "is not set to a number"
	assert_equal "$(count_set_calls)" "0"
}
