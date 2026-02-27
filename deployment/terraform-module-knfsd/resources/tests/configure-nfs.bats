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
	export NUM_NFS_THREADS=64

	run configure_nfs
	assert_success

	assert [ -f /etc/nfs.conf.d/knfsd.conf ]
	assert_equal "$(nfsconf --get nfsd threads)" 64
}
