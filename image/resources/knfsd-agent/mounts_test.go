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
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadMounts(t *testing.T) {
	t.Parallel()
	fs, err := procfs.NewFS("./testdata/proc/")
	require.NoError(t, err)

	proc, err := fs.Proc(1)
	require.NoError(t, err)

	mounts, err := readMounts(proc, "/srv/nfs/")
	require.NoError(t, err)

	expected, err := os.ReadFile("testdata/expected/mounts.json")
	require.NoError(t, err)

	actual, err := json.MarshalIndent(&mounts, "", "  ")
	require.NoError(t, err)
	assert.JSONEq(t, string(expected), string(actual))
}

func TestReadMountStats(t *testing.T) {
	t.Parallel()
	fs, err := procfs.NewFS("./testdata/proc/")
	require.NoError(t, err)

	proc, err := fs.Proc(1)
	require.NoError(t, err)

	mounts, err := readMountStats(proc, "/srv/nfs/")
	require.NoError(t, err)

	expected, err := os.ReadFile("testdata/expected/mountstats.json")
	require.NoError(t, err)

	actual, err := json.MarshalIndent(&mounts, "", "  ")
	require.NoError(t, err)
	assert.JSONEq(t, string(expected), string(actual))
}
