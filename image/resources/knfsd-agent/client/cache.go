/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package client

import "fmt"

type CacheUsageResponse struct {
	BytesTotal     uint64 `json:"bytesTotal"`
	BytesUsed      uint64 `json:"bytesUsed"`
	BytesFree      uint64 `json:"bytesFree"`
	BytesAvailable uint64 `json:"bytesAvailable"`

	BlockSize       int64  `json:"blockSize"`
	BlocksTotal     uint64 `json:"blocksTotal"`
	BlocksUsed      uint64 `json:"blocksUsed"`
	BlocksFree      uint64 `json:"blocksFree"`
	BlocksAvailable uint64 `json:"blocksAvailable"`

	FilesTotal uint64 `json:"filesTotal"`
	FilesUsed  uint64 `json:"filesUsed"`
	FilesFree  uint64 `json:"filesFree"`
}

func (c *KnfsdAgentClient) CacheUsage() (*CacheUsageResponse, error) {
	var v *CacheUsageResponse
	err := c.get("api/v1/cache/usage", &v)
	return v, err
}

// CacheStatsResponse holds the netfslib counter groups needed to tell whether
// the cache is serving reads, not merely absorbing writes.
type CacheStatsResponse struct {
	DownOps     DownOpsStats     `json:"downOps"`
	CacheReads  CacheReadsStats  `json:"cacheReads"`
	CacheWrites CacheWritesStats `json:"cacheWrites"`
}

// DownOpsStats counts fetches from the source filer, i.e. cache misses.
type DownOpsStats struct {
	Downloads uint64 `json:"downloads"`
	Done      uint64 `json:"done"`
	Failed    uint64 `json:"failed"`
	Instead   uint64 `json:"instead"`
}

// CacheReadsStats counts reads served from FS-Cache. Requests staying at zero
// while data is known to be cached means the cache is never being read from.
type CacheReadsStats struct {
	Requests uint64 `json:"requests"`
	Done     uint64 `json:"done"`
	Failed   uint64 `json:"failed"`
}

// CacheWritesStats counts writes into FS-Cache, i.e. cache population.
type CacheWritesStats struct {
	Requests uint64 `json:"requests"`
	Done     uint64 `json:"done"`
	Failed   uint64 `json:"failed"`
}

func (c *KnfsdAgentClient) CacheStats() (*CacheStatsResponse, error) {
	var v *CacheStatsResponse
	err := c.get("api/v1/cache/stats", &v)
	return v, err
}

// Modes accepted by /proc/sys/vm/drop_caches, per proc_sys_vm(5).
const (
	// DropCachesPageCache frees pagecache only. Sufficient to force reads down
	// to FS-Cache without discarding dentry and inode caches.
	DropCachesPageCache = 1
	// DropCachesSlab frees dentries and inodes only.
	DropCachesSlab = 2
	// DropCachesAll frees pagecache, dentries and inodes.
	DropCachesAll = 3
)

// CacheDropResponse reports the mode that was applied.
type CacheDropResponse struct {
	Mode int `json:"mode"`
}

// DropCaches frees the proxy's kernel caches so that subsequent reads must come
// from FS-Cache rather than the page cache.
//
// mode is validated here as well as server-side, so an invalid value fails
// before a request is made.
func (c *KnfsdAgentClient) DropCaches(mode int) (*CacheDropResponse, error) {
	switch mode {
	case DropCachesPageCache, DropCachesSlab, DropCachesAll:
	default:
		return nil, fmt.Errorf("invalid drop_caches mode %d, must be 1, 2 or 3", mode)
	}

	var v *CacheDropResponse
	err := c.post(fmt.Sprintf("api/v1/cache/drop?mode=%d", mode), &v)
	return v, err
}
