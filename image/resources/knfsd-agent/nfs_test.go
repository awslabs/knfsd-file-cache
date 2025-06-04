/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/prometheus/procfs"
	"github.com/prometheus/procfs/nfs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadNFSClientStats(t *testing.T) {
	t.Skip("missing client stats") // skip test as no NFS server/client running

	fs, err := procfs.NewFS("testdata/proc")
	require.NoError(t, err)

	proc, err := fs.Proc(1)
	require.NoError(t, err)

	nfsFS, err := nfs.NewFS("testdata/proc")
	require.NoError(t, err)

	stats, err := readNFSClientStats(nfsFS, proc, "/srv/nfs/")
	require.NoError(t, err)

	expected, err := os.ReadFile("testdata/expected/nfs-client.json")
	require.NoError(t, err)

	actual, err := json.MarshalIndent(&stats, "", "  ")
	require.NoError(t, err)
	assert.JSONEq(t, string(expected), string(actual))
}

func TestReadNFSServerStats(t *testing.T) {
	fs, err := nfs.NewFS("testdata/proc")
	require.NoError(t, err)

	stats, err := readNFSServerStats(fs)
	require.NoError(t, err)

	expected, err := os.ReadFile("testdata/expected/nfs-server.json")
	require.NoError(t, err)

	actual, err := json.MarshalIndent(&stats, "", "  ")
	require.NoError(t, err)
	assert.JSONEq(t, string(expected), string(actual))
}
