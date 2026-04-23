/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package mounts

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/prometheus/procfs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap/zaptest"
)

func TestSplitNFSDevice(t *testing.T) {
	t.Parallel()
	var server, path string

	server, path = splitNFSDevice("example.com:/files/assets")
	assert.Equal(t, "example.com", server)
	assert.Equal(t, "/files/assets", path)

	// paths can contain colons, check that we only split the first colon
	server, path = splitNFSDevice("example.com:/files:assets")
	assert.Equal(t, "example.com", server)
	assert.Equal(t, "/files:assets", path)

	server, path = splitNFSDevice("")
	assert.Equal(t, "", server)
	assert.Equal(t, "", path)

	server, path = splitNFSDevice("foo")
	assert.Equal(t, "", server)
	assert.Equal(t, "foo", path)
}

// writeFakeProc builds a minimal /proc/<pid> tree under procRoot with the
// supplied mountstats and mountinfo contents and returns a procfs.Proc that
// reads from it.
func writeFakeProc(t *testing.T, procRoot string, pid int, mountstats, mountinfo string) procfs.Proc {
	t.Helper()
	pidDir := filepath.Join(procRoot, strconv.Itoa(pid))
	require.NoError(t, os.MkdirAll(pidDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(pidDir, "mountstats"), []byte(mountstats), 0o600))
	require.NoError(t, os.WriteFile(filepath.Join(pidDir, "mountinfo"), []byte(mountinfo), 0o600))

	fs, err := procfs.NewFS(procRoot)
	require.NoError(t, err)
	p, err := fs.Proc(pid)
	require.NoError(t, err)
	return p
}

// TestAggregateNFSStats_ResolvesLocalhostDevice verifies the splitNFSDevice /
// resolveServer wiring in aggregateNFSStats: a mount that appears as
// 127.0.0.1 in mountstats must have its Device rewritten to the resolved DNS
// name, and the aggregator must key the resulting nfsStatsGroup on that
// resolved name rather than on 127.0.0.1.
func TestAggregateNFSStats_ResolvesLocalhostDevice(t *testing.T) {
	t.Parallel()

	stateDir := t.TempDir()
	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, stateDir, configName, "fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, stateDir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(stateDir, configName)},
		FsID:       "fs-abc123",
	})

	// Fake /proc/1/mountstats with a single NFS4 mount that appears as
	// 127.0.0.1 (the efs-proxy loopback address).
	mountstats := "device 127.0.0.1:/ mounted on /srv/nfs/efs with fstype nfs4 statvers=1.1\n"

	// Matching mountinfo entry. Field order per proc(5):
	// id parent major:minor root mountpoint options - fstype source superopts
	mountinfo := "30 29 0:42 / /srv/nfs/efs rw,relatime - nfs4 127.0.0.1:/ rw,vers=4.1\n"

	procRoot := t.TempDir()
	p := writeFakeProc(t, procRoot, 1, mountstats, mountinfo)

	logger := zaptest.NewLogger(t)
	s := &mountsScraper{
		cfg:    &Config{EFSStateDir: stateDir},
		logger: logger,
		p:      p,
		efsRes: &efsResolver{stateDir: stateDir, logger: logger},
	}

	agg, err := s.aggregateNFSStats()
	require.NoError(t, err)

	_, hasLoopback := agg["127.0.0.1"]
	assert.False(t, hasLoopback, "aggregator should not be keyed on 127.0.0.1 after resolution")

	grp, hasResolved := agg["fs-abc123.efs.eu-west-2.amazonaws.com"]
	require.True(t, hasResolved, "aggregator should be keyed on the resolved DNS name")
	assert.Equal(t, "fs-abc123.efs.eu-west-2.amazonaws.com", grp.server)
	_, hasLocalPath := grp.localPaths["/srv/nfs/efs"]
	assert.True(t, hasLocalPath, "local path should be tracked under the resolved group")
}

// TestAggregateNFSStats_CoalescesMultipleLocalhostMounts verifies that two
// separate 127.0.0.1 mounts which resolve to different DNS names end up in
// distinct aggregator entries, and that two mounts which resolve to the
// same DNS name are coalesced into a single entry.
func TestAggregateNFSStats_CoalescesMultipleLocalhostMounts(t *testing.T) {
	t.Parallel()

	stateDir := t.TempDir()

	efsConfig := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, stateDir, efsConfig, "fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, stateDir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(stateDir, efsConfig)},
		FsID:       "fs-abc123",
	})

	s3Config := "stunnel-config.fs-def456.srv.nfs.s3files.30123"
	writeStunnelConfig(t, stateDir, s3Config, "fs-def456.s3files.us-east-1.on.aws")
	writeStateFile(t, stateDir, "fs-def456.srv.nfs.s3files.30123", efsStateFile{
		Mountpoint: "/srv/nfs/s3files",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(stateDir, s3Config)},
		FsID:       "fs-def456",
	})

	// A third EFS state file pointing at the same FS as the first entry, but
	// mounted at a different local path. Both should collapse into a single
	// aggregator group keyed by the resolved hostname.
	efsConfig2 := "stunnel-config.fs-abc123.mnt.efs.12345"
	writeStunnelConfig(t, stateDir, efsConfig2, "fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, stateDir, "fs-abc123.mnt.efs.12345", efsStateFile{
		Mountpoint: "/mnt/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(stateDir, efsConfig2)},
		FsID:       "fs-abc123",
	})

	mountstats := "" +
		"device 127.0.0.1:/ mounted on /srv/nfs/efs with fstype nfs4 statvers=1.1\n" +
		"per-op statistics\n" +
		"\n" +
		"device 127.0.0.1:/ mounted on /mnt/efs with fstype nfs4 statvers=1.1\n" +
		"per-op statistics\n" +
		"\n" +
		"device 127.0.0.1:/ mounted on /srv/nfs/s3files with fstype nfs4 statvers=1.1\n" +
		"per-op statistics\n"

	mountinfo := "" +
		"30 29 0:42 / /srv/nfs/efs rw,relatime - nfs4 127.0.0.1:/ rw,vers=4.1\n" +
		"31 29 0:43 / /mnt/efs rw,relatime - nfs4 127.0.0.1:/ rw,vers=4.1\n" +
		"32 29 0:44 / /srv/nfs/s3files rw,relatime - nfs4 127.0.0.1:/ rw,vers=4.1\n"

	procRoot := t.TempDir()
	p := writeFakeProc(t, procRoot, 1, mountstats, mountinfo)

	logger := zaptest.NewLogger(t)
	s := &mountsScraper{
		cfg:    &Config{EFSStateDir: stateDir},
		logger: logger,
		p:      p,
		efsRes: &efsResolver{stateDir: stateDir, logger: logger},
	}

	agg, err := s.aggregateNFSStats()
	require.NoError(t, err)

	_, hasLoopback := agg["127.0.0.1"]
	assert.False(t, hasLoopback, "aggregator must not retain the unresolved 127.0.0.1 key")
	assert.Len(t, agg, 2, "two distinct resolved servers expected")

	efsGrp, ok := agg["fs-abc123.efs.eu-west-2.amazonaws.com"]
	require.True(t, ok)
	assert.Equal(t, "fs-abc123.efs.eu-west-2.amazonaws.com", efsGrp.server)
	_, hasEFS := efsGrp.localPaths["/srv/nfs/efs"]
	_, hasMnt := efsGrp.localPaths["/mnt/efs"]
	assert.True(t, hasEFS, "both local paths must be tracked when resolved to the same host")
	assert.True(t, hasMnt, "both local paths must be tracked when resolved to the same host")

	s3Grp, ok := agg["fs-def456.s3files.us-east-1.on.aws"]
	require.True(t, ok)
	assert.Equal(t, "fs-def456.s3files.us-east-1.on.aws", s3Grp.server)
}

// TestAggregateNFSStats_UnresolvedLocalhostFallsBack verifies that when the
// resolver cannot map 127.0.0.1 (e.g. no matching state file), the mount is
// still aggregated and the 127.0.0.1 key is preserved rather than dropped.
func TestAggregateNFSStats_UnresolvedLocalhostFallsBack(t *testing.T) {
	t.Parallel()

	stateDir := t.TempDir() // empty: resolver will return ""

	mountstats := "device 127.0.0.1:/ mounted on /srv/nfs/efs with fstype nfs4 statvers=1.1\n"
	mountinfo := "30 29 0:42 / /srv/nfs/efs rw,relatime - nfs4 127.0.0.1:/ rw,vers=4.1\n"

	procRoot := t.TempDir()
	p := writeFakeProc(t, procRoot, 1, mountstats, mountinfo)

	logger := zaptest.NewLogger(t)
	s := &mountsScraper{
		cfg:    &Config{EFSStateDir: stateDir},
		logger: logger,
		p:      p,
		efsRes: &efsResolver{stateDir: stateDir, logger: logger},
	}

	agg, err := s.aggregateNFSStats()
	require.NoError(t, err)

	grp, ok := agg["127.0.0.1"]
	require.True(t, ok, "unresolved 127.0.0.1 mounts must still be aggregated")
	assert.Equal(t, "127.0.0.1", grp.server)
}

// TestAggregateNFSStats_NonLocalhostUntouched verifies that regular NFS
// mounts (not using the 127.0.0.1 efs-proxy loopback) bypass the resolver
// entirely and are aggregated under their original device hostname.
func TestAggregateNFSStats_NonLocalhostUntouched(t *testing.T) {
	t.Parallel()

	stateDir := t.TempDir()

	mountstats := "device nfs.example.com:/exports mounted on /mnt/nfs with fstype nfs4 statvers=1.1\n"
	mountinfo := "40 29 0:50 / /mnt/nfs rw,relatime - nfs4 nfs.example.com:/exports rw,vers=4.1\n"

	procRoot := t.TempDir()
	p := writeFakeProc(t, procRoot, 1, mountstats, mountinfo)

	logger := zaptest.NewLogger(t)
	s := &mountsScraper{
		cfg:    &Config{EFSStateDir: stateDir},
		logger: logger,
		p:      p,
		efsRes: &efsResolver{stateDir: stateDir, logger: logger},
	}

	agg, err := s.aggregateNFSStats()
	require.NoError(t, err)

	grp, ok := agg["nfs.example.com"]
	require.True(t, ok)
	assert.Equal(t, "nfs.example.com", grp.server)
}
