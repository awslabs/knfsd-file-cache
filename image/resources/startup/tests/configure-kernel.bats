# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function setup() {
	bats_load_library bats-support
	bats_load_library bats-assert
	load ./common.bash
	load ../proxy-startup.sh
}

# Helper: assert /tmp/sysctl contains a line matching the given pattern (grep -E)
function assert_sysctl_line() {
	local pattern="$1"
	grep -E "$pattern" /tmp/sysctl
}

@test "set sunrpc.tcp_slot_table_entries" {
	export TCP_SLOT_TABLE_ENTRIES=256
	run configure_kernel
	assert_success
	assert_sysctl_line 'sunrpc\.tcp_slot_table_entries=256'
}

@test "set sunrpc.tcp_max_slot_table_entries" {
	export TCP_MAX_SLOT_TABLE_ENTRIES=512
	run configure_kernel
	assert_success
	assert_sysctl_line 'sunrpc\.tcp_max_slot_table_entries=512'
}

@test "set vm.vfs_cache_pressure" {
	export VFS_CACHE_PRESSURE=10
	run configure_kernel
	assert_success
	assert_sysctl_line 'vm\.vfs_cache_pressure=10'
}

@test "set vm.min_free_kbytes" {
	run configure_kernel
	assert_success
	assert_sysctl_line 'vm\.min_free_kbytes=[0-9]+'
}

@test "set vm.compaction_proactiveness" {
	run configure_kernel
	assert_success
	assert_sysctl_line 'vm\.compaction_proactiveness=0'
}

@test "set vm.dirty_ratio" {
	run configure_kernel
	assert_success
	assert_sysctl_line 'vm\.dirty_ratio=40'
}

@test "set vm.dirty_background_ratio" {
	run configure_kernel
	assert_success
	assert_sysctl_line 'vm\.dirty_background_ratio=20'
}

@test "set vm.swappiness" {
	run configure_kernel
	assert_success
	assert_sysctl_line 'vm\.swappiness=5'
}

@test "invokes sysctl with -w" {
	run configure_kernel
	assert_success
	while IFS= read -r line; do
		assert_equal "${line:0:3}" '-w '
	done < /tmp/sysctl
}
