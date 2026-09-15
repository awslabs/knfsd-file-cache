/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"bufio"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-agent/client"
)

// fscacheStatsPath is the netfslib and FS-Cache counter file. It only exists
// when the kernel was built with CONFIG_FSCACHE_STATS.
const fscacheStatsPath = "/proc/fs/fscache/stats"

// handleCacheStats reports the subset of /proc/fs/fscache/stats needed to tell
// whether the cache is actually being used, as opposed to merely written to.
//
// The distinction matters: cache writes and cache reads fail independently. A
// cache can be filling correctly (CaWrOps climbing) while never serving a single
// read (CaRdOps.RD stuck at zero), in which case every request still goes to the
// source filer and the cache is pure overhead. Disk usage alone cannot detect
// that, because the writes still land.
func handleCacheStats(*http.Request) (*client.CacheStatsResponse, error) {
	return parseCacheStats(fscacheStatsPath)
}

// parseCacheStats reads the counter groups this endpoint exposes.
//
// The file is a series of "Category: key=value key=value" lines. Unknown
// categories and malformed lines are skipped rather than failing the request,
// because the counter set varies between kernel versions and a single new line
// should not break the endpoint.
func parseCacheStats(path string) (*client.CacheStatsResponse, error) {
	file, err := os.Open(path) // #nosec G304 -- fixed procfs path, not user input
	if err != nil {
		return nil, fmt.Errorf("failed to open %s: %w", path, err)
	}
	defer file.Close()

	stats := &client.CacheStatsResponse{}
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		category, values, ok := parseStatsLine(scanner.Text())
		if !ok {
			continue
		}

		switch category {
		case "DownOps":
			stats.DownOps.Downloads = values["DL"]
			stats.DownOps.Done = values["ds"]
			stats.DownOps.Failed = values["df"]
			stats.DownOps.Instead = values["di"]
		case "CaRdOps":
			stats.CacheReads.Requests = values["RD"]
			stats.CacheReads.Done = values["rs"]
			stats.CacheReads.Failed = values["rf"]
		case "CaWrOps":
			stats.CacheWrites.Requests = values["WR"]
			stats.CacheWrites.Done = values["ws"]
			stats.CacheWrites.Failed = values["wf"]
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading %s: %w", path, err)
	}

	return stats, nil
}

// parseStatsLine splits one "Category: key=value key=value" line. Returns
// ok=false for blank lines, the "-- FS-Cache statistics --" separator, and
// anything else that does not match the expected shape.
func parseStatsLine(raw string) (category string, values map[string]uint64, ok bool) {
	line := strings.TrimSpace(raw)
	if line == "" || strings.HasPrefix(line, "--") {
		return "", nil, false
	}

	name, rest, found := strings.Cut(line, ":")
	if !found {
		return "", nil, false
	}

	values = make(map[string]uint64)
	for field := range strings.FieldsSeq(rest) {
		key, value, found := strings.Cut(field, "=")
		if !found {
			continue
		}
		// Skip unparsable values rather than failing; a counter this endpoint
		// does not expose should never break the ones it does.
		if n, err := strconv.ParseUint(value, 10, 64); err == nil {
			values[key] = n
		}
	}

	return strings.TrimSpace(name), values, true
}
