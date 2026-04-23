/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package mounts

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"go.uber.org/zap"
)

// efsResolver resolves the real server DNS name for EFS and S3 Files mounts
// that appear as 127.0.0.1 in /proc/self/mountstats due to the local proxy
// used by efs-utils.
type efsResolver struct {
	stateDir string
	logger   *zap.Logger

	// cache holds parsed state files for the current scrape cycle
	cache []efsStateFile
	// cacheLoaded indicates whether the cache has been populated this cycle
	cacheLoaded bool
}

type efsStateFile struct {
	Mountpoint string   `json:"mountpoint"`
	Cmd        []string `json:"cmd"`
	FsID       string   `json:"fsId"`
	filename   string
}

var connectRegexp = regexp.MustCompile(`connect\s*=\s*(.+):(\d+)`)

// resetCache clears the cached state files so they are re-read on the next
// call to resolveServer. Call this at the start of each scrape cycle.
func (r *efsResolver) resetCache() {
	r.cache = nil
	r.cacheLoaded = false
}

// resolveServer attempts to find the real DNS name for a mount that uses the
// efs-utils local proxy. It correlates the given mountPath (from mountstats)
// with efs-utils state files in stateDir.
//
// Returns ("", nil) if no matching state file is found (graceful no-op).
func (r *efsResolver) resolveServer(mountPath string) (string, error) {
	if err := r.ensureCache(); err != nil {
		return "", err
	}

	for _, sf := range r.cache {
		if sf.Mountpoint != mountPath {
			continue
		}

		configPath := findStunnelConfigPath(sf.Cmd)
		if configPath == "" {
			r.logger.Warn("efs-utils state file has no stunnel config in cmd",
				zap.String("mount", mountPath),
				zap.String("file", sf.filename),
			)
			return "", nil
		}

		host, err := r.parseConnectHost(configPath)
		if err != nil {
			r.logger.Warn("failed to parse stunnel config",
				zap.String("mount", mountPath),
				zap.String("config", configPath),
				zap.Error(err),
			)
			return "", nil
		}

		if host == "" {
			r.logger.Warn("no connect line found in stunnel config",
				zap.String("mount", mountPath),
				zap.String("config", configPath),
			)
			return "", nil
		}

		return host, nil
	}

	return "", nil
}

// ensureCache loads and parses all state files from stateDir if not already
// cached for this scrape cycle. File access is scoped to stateDir via os.Root
// to prevent directory traversal.
func (r *efsResolver) ensureCache() error {
	if r.cacheLoaded {
		return nil
	}
	r.cacheLoaded = true

	entries, err := os.ReadDir(r.stateDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}

	root, err := os.OpenRoot(r.stateDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer root.Close()

	for _, e := range entries {
		if e.IsDir() {
			continue
		}

		name := e.Name()

		// Skip stunnel config files (not JSON state files)
		if strings.HasPrefix(name, "stunnel-config.") {
			continue
		}

		sf, err := parseStateFile(root, name)
		if err != nil {
			r.logger.Warn("failed to parse efs-utils state file",
				zap.String("file", filepath.Join(r.stateDir, name)),
				zap.Error(err),
			)
			continue
		}
		sf.filename = name
		r.cache = append(r.cache, sf)
	}

	return nil
}

// parseStateFile reads and unmarshals a single efs-utils state JSON file.
// The file is opened relative to root to scope access under the state dir.
func parseStateFile(root *os.Root, name string) (efsStateFile, error) {
	data, err := root.ReadFile(name)
	if err != nil {
		return efsStateFile{}, err
	}

	var sf efsStateFile
	if err := json.Unmarshal(data, &sf); err != nil {
		return efsStateFile{}, err
	}
	return sf, nil
}

// findStunnelConfigPath extracts the stunnel config file path from the cmd
// array in the state file. The config path is the element that contains
// "stunnel-config.".
func findStunnelConfigPath(cmd []string) string {
	for _, arg := range cmd {
		if strings.Contains(arg, "stunnel-config.") {
			return arg
		}
	}
	return ""
}

// parseConnectHost reads a stunnel/efs-proxy config file and extracts the
// host from the "connect = host:port" line. The config file must live under
// the resolver's stateDir; file access is scoped via os.Root to prevent
// directory traversal.
func (r *efsResolver) parseConnectHost(configPath string) (string, error) {
	dir, name := filepath.Split(configPath)
	if filepath.Clean(dir) != filepath.Clean(r.stateDir) {
		return "", fmt.Errorf("stunnel config path %q is outside state dir %q", configPath, r.stateDir)
	}

	root, err := os.OpenRoot(r.stateDir)
	if err != nil {
		return "", err
	}
	defer root.Close()

	f, err := root.Open(name)
	if err != nil {
		return "", err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		matches := connectRegexp.FindStringSubmatch(line)
		if matches != nil {
			return matches[1], nil
		}
	}

	if err := scanner.Err(); err != nil {
		return "", err
	}

	return "", nil
}
