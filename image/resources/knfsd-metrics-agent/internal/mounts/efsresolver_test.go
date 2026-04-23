/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package mounts

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
	"go.uber.org/zap/zaptest"
	"go.uber.org/zap/zaptest/observer"
)

func writeStateFile(t *testing.T, dir, name string, sf efsStateFile) {
	t.Helper()
	data, err := json.Marshal(sf)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(dir, name), data, 0o600))
}

func writeStunnelConfig(t *testing.T, dir, name, host string) {
	t.Helper()
	content := "[efs-proxy]\nclient = yes\nconnect = " + host + ":2049\n"
	require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600))
}

func newTestResolver(t *testing.T, dir string) *efsResolver {
	t.Helper()
	return &efsResolver{
		stateDir: dir,
		logger:   zaptest.NewLogger(t),
	}
}

func TestResolveServer_EFSStandard(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, configName, "fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "fs-abc123.efs.eu-west-2.amazonaws.com", host)
}

func TestResolveServer_EFSWithAZ(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, configName, "eu-west-2a.fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "eu-west-2a.fs-abc123.efs.eu-west-2.amazonaws.com", host)
}

func TestResolveServer_EFSChinaRegion(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, configName, "fs-abc123.efs.cn-north-1.amazonaws.com.cn")
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "fs-abc123.efs.cn-north-1.amazonaws.com.cn", host)
}

func TestResolveServer_S3FilesStandard(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-def456.srv.nfs.s3files.30123"
	writeStunnelConfig(t, dir, configName, "fs-def456.s3files.eu-west-2.on.aws")
	writeStateFile(t, dir, "fs-def456.srv.nfs.s3files.30123", efsStateFile{
		Mountpoint: "/srv/nfs/s3files",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-def456",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/s3files")
	require.NoError(t, err)
	assert.Equal(t, "fs-def456.s3files.eu-west-2.on.aws", host)
}

func TestResolveServer_S3FilesWithAZID(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-def456.srv.nfs.s3files.30123"
	writeStunnelConfig(t, dir, configName, "use1-az1.fs-def456.s3files.us-east-1.on.aws")
	writeStateFile(t, dir, "fs-def456.srv.nfs.s3files.30123", efsStateFile{
		Mountpoint: "/srv/nfs/s3files",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-def456",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/s3files")
	require.NoError(t, err)
	assert.Equal(t, "use1-az1.fs-def456.s3files.us-east-1.on.aws", host)
}

func TestResolveServer_MountTargetIP(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, configName, "192.168.1.100")
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "192.168.1.100", host)
}

func TestResolveServer_TildePrefix(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, configName, "fs-abc123.efs.eu-west-2.amazonaws.com")
	// Write state file with ~ prefix (pre-watchdog rename)
	writeStateFile(t, dir, "~fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "fs-abc123.efs.eu-west-2.amazonaws.com", host)
}

func TestResolveServer_MultipleFilesystems(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()

	// EFS mount
	efsConfig := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, efsConfig, "fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, efsConfig)},
		FsID:       "fs-abc123",
	})

	// S3 Files mount
	s3Config := "stunnel-config.fs-def456.srv.nfs.s3files.30123"
	writeStunnelConfig(t, dir, s3Config, "fs-def456.s3files.us-east-1.on.aws")
	writeStateFile(t, dir, "fs-def456.srv.nfs.s3files.30123", efsStateFile{
		Mountpoint: "/srv/nfs/s3files",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, s3Config)},
		FsID:       "fs-def456",
	})

	r := newTestResolver(t, dir)

	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "fs-abc123.efs.eu-west-2.amazonaws.com", host)

	host, err = r.resolveServer("/srv/nfs/s3files")
	require.NoError(t, err)
	assert.Equal(t, "fs-def456.s3files.us-east-1.on.aws", host)
}

func TestResolveServer_NoMatchingStateFile(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()

	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, configName, "fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/other")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_EmptyStateDir(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_NonexistentStateDir(t *testing.T) {
	t.Parallel()
	r := newTestResolver(t, "/nonexistent/path/efs-state")
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_MalformedJSON(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "fs-abc123.srv.nfs.efs.20594"), []byte("{invalid json"), 0o600))

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_MissingStunnelConfig(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, "stunnel-config.fs-abc123.srv.nfs.efs.20594")},
		FsID:       "fs-abc123",
	})
	// Deliberately do NOT write the stunnel config file

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_StunnelConfigNoConnectLine(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	require.NoError(t, os.WriteFile(filepath.Join(dir, configName), []byte("[efs-proxy]\nclient = yes\n"), 0o600))
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_StunnelConfigFilesSkipped(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	// Write a stunnel-config file directly (not JSON); ensure it's not parsed as a state file
	require.NoError(t, os.WriteFile(
		filepath.Join(dir, "stunnel-config.fs-abc123.srv.nfs.efs.20594"),
		[]byte("[efs-proxy]\nclient = yes\nconnect = fs-abc123.efs.eu-west-2.amazonaws.com:2049\n"),
		0o600,
	))

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_NoCmdStunnelConfig(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy"},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
}

func TestResolveServer_CacheResetBetweenCycles(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()

	configName := "stunnel-config.fs-abc123.srv.nfs.efs.20594"
	writeStunnelConfig(t, dir, configName, "fs-abc123.efs.eu-west-2.amazonaws.com")
	writeStateFile(t, dir, "fs-abc123.srv.nfs.efs.20594", efsStateFile{
		Mountpoint: "/srv/nfs/efs",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, configName)},
		FsID:       "fs-abc123",
	})

	r := newTestResolver(t, dir)

	// First cycle
	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "fs-abc123.efs.eu-west-2.amazonaws.com", host)

	// Add a second mount between cycles
	config2 := "stunnel-config.fs-def456.srv.nfs.s3files.30123"
	writeStunnelConfig(t, dir, config2, "fs-def456.s3files.eu-west-2.on.aws")
	writeStateFile(t, dir, "fs-def456.srv.nfs.s3files.30123", efsStateFile{
		Mountpoint: "/srv/nfs/s3files",
		Cmd:        []string{"/usr/bin/efs-proxy", filepath.Join(dir, config2)},
		FsID:       "fs-def456",
	})

	// Without reset, the new file is not seen
	host, err = r.resolveServer("/srv/nfs/s3files")
	require.NoError(t, err)
	assert.Equal(t, "", host, "should not find new mount without cache reset")

	// Reset and re-resolve
	r.resetCache()
	host, err = r.resolveServer("/srv/nfs/s3files")
	require.NoError(t, err)
	assert.Equal(t, "fs-def456.s3files.eu-west-2.on.aws", host)
}

func TestParseConnectHost_VariousFormats(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		content  string
		expected string
	}{
		{
			name:     "EFS standard",
			content:  "[efs-proxy]\nclient = yes\nconnect = fs-abc123.efs.eu-west-2.amazonaws.com:2049\n",
			expected: "fs-abc123.efs.eu-west-2.amazonaws.com",
		},
		{
			name:     "EFS with AZ prefix",
			content:  "[efs-proxy]\nconnect = eu-west-2a.fs-abc123.efs.eu-west-2.amazonaws.com:2049\n",
			expected: "eu-west-2a.fs-abc123.efs.eu-west-2.amazonaws.com",
		},
		{
			name:     "EFS China region",
			content:  "[efs-proxy]\nconnect = fs-abc123.efs.cn-north-1.amazonaws.com.cn:2049\n",
			expected: "fs-abc123.efs.cn-north-1.amazonaws.com.cn",
		},
		{
			name:     "S3 Files standard",
			content:  "[efs-proxy]\nconnect = fs-abc123.s3files.eu-west-2.on.aws:2049\n",
			expected: "fs-abc123.s3files.eu-west-2.on.aws",
		},
		{
			name:     "S3 Files with AZ ID",
			content:  "[efs-proxy]\nconnect = use1-az1.fs-abc123.s3files.us-east-1.on.aws:2049\n",
			expected: "use1-az1.fs-abc123.s3files.us-east-1.on.aws",
		},
		{
			name:     "mounttargetip",
			content:  "[efs-proxy]\nconnect = 192.168.1.100:2049\n",
			expected: "192.168.1.100",
		},
		{
			name:     "no connect line",
			content:  "[efs-proxy]\nclient = yes\n",
			expected: "",
		},
		{
			name:     "connect with extra spaces",
			content:  "[efs-proxy]\nconnect  =  fs-abc123.efs.eu-west-2.amazonaws.com:2049\n",
			expected: "fs-abc123.efs.eu-west-2.amazonaws.com",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			configPath := filepath.Join(dir, "stunnel-config.test")
			require.NoError(t, os.WriteFile(configPath, []byte(tc.content), 0o600))

			r := newTestResolver(t, dir)
			host, err := r.parseConnectHost(configPath)
			require.NoError(t, err)
			assert.Equal(t, tc.expected, host)
		})
	}
}

func TestFindStunnelConfigPath(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		cmd      []string
		expected string
	}{
		{
			name:     "standard efs-proxy cmd",
			cmd:      []string{"/usr/bin/efs-proxy", "/var/run/efs/stunnel-config.fs-abc.srv.nfs.efs.20594"},
			expected: "/var/run/efs/stunnel-config.fs-abc.srv.nfs.efs.20594",
		},
		{
			name:     "no config in cmd",
			cmd:      []string{"/usr/bin/efs-proxy"},
			expected: "",
		},
		{
			name:     "empty cmd",
			cmd:      nil,
			expected: "",
		},
		{
			name:     "stunnel with flags",
			cmd:      []string{"stunnel", "--foreground", "/var/run/efs/stunnel-config.fs-abc.mnt.efs.12345"},
			expected: "/var/run/efs/stunnel-config.fs-abc.mnt.efs.12345",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			result := findStunnelConfigPath(tc.cmd)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestResolveServer_LogsWarningOnMalformedJSON(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "bad-state-file"), []byte("not json"), 0o600))

	core, observed := observer.New(zap.WarnLevel)
	logger := zap.New(core)
	r := &efsResolver{stateDir: dir, logger: logger}

	host, err := r.resolveServer("/srv/nfs/efs")
	require.NoError(t, err)
	assert.Equal(t, "", host)
	assert.Equal(t, 1, observed.Len(), "expected a warning log for malformed JSON")
}
