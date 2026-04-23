# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function setup_file() {
	: > /etc/nfs.conf
	rm -rf /etc/nfs.conf.d
	mkdir -p /etc/nfs.conf.d
}

function setup() {
	bats_load_library bats-support
	bats_load_library bats-assert
	load ./common.bash
	load ../proxy-startup.sh

	export READ_AHEAD=8388608
	export DISABLED_NFS_VERSIONS=""
	export NUM_NFS_THREADS=64
}

@test "disable nfs versions " {
	export DISABLED_NFS_VERSIONS="3,4.0,4.2"

	run configure_nfs
	assert_success

	assert [ -f /etc/nfs.conf.d/knfsd.conf ]
	assert_equal "$(nfsconf --get nfsd vers2)" no
	assert_equal "$(nfsconf --get nfsd vers3)" no
	assert_equal "$(nfsconf --get nfsd vers4)" "" # not set
	assert_equal "$(nfsconf --get nfsd vers4.0)" no
	assert_equal "$(nfsconf --get nfsd vers4.1)" "" # not set
	assert_equal "$(nfsconf --get nfsd vers4.2)" no
}

@test "set RPC thread count " {
	export NUM_NFS_THREADS=128

	run configure_nfs
	assert_success

	assert [ -f /etc/nfs.conf.d/knfsd.conf ]
	assert_equal "$(nfsconf --get nfsd threads)" 128
}

@test "set NFS readahead " {
	run configure_nfs
	assert_success

	assert [ -f /etc/nfs.conf.d/knfsd.conf ]
	assert_equal "$(nfsconf --get nfsrahead nfs)" 8192
	assert_equal "$(nfsconf --get nfsrahead nfs4)" 8192
	assert_equal "$(nfsconf --get nfsrahead default)" 8192
}

@test "set NFS readahead with custom value " {
	# shellcheck disable=SC2030,SC2031
	export READ_AHEAD=15728640

	run configure_nfs
	assert_success

	assert [ -f /etc/nfs.conf.d/knfsd.conf ]
	assert_equal "$(nfsconf --get nfsrahead nfs)" 15360
	assert_equal "$(nfsconf --get nfsrahead nfs4)" 15360
	assert_equal "$(nfsconf --get nfsrahead default)" 15360
}
