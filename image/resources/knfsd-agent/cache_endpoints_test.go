/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-agent/client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseDropCachesMode(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		raw     string
		want    int
		wantErr bool
	}{
		// Default matches the existing client-side helper, which writes "3".
		{name: "empty defaults to all", raw: "", want: client.DropCachesAll},
		{name: "pagecache", raw: "1", want: client.DropCachesPageCache},
		{name: "slab", raw: "2", want: client.DropCachesSlab},
		{name: "all", raw: "3", want: client.DropCachesAll},

		// Anything outside the allowlist must be rejected, because the value is
		// written to a procfs file.
		{name: "zero rejected", raw: "0", wantErr: true},
		{name: "four rejected", raw: "4", wantErr: true},
		{name: "negative rejected", raw: "-1", wantErr: true},
		{name: "non numeric rejected", raw: "all", wantErr: true},
		{name: "injection rejected", raw: "3; rm -rf /", wantErr: true},
		{name: "whitespace rejected", raw: " 3", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := parseDropCachesMode(tt.raw)
			if tt.wantErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestHandleCacheDropRejectsNonPost(t *testing.T) {
	t.Parallel()

	// GET must be rejected even though every other endpoint accepts it, because
	// this endpoint mutates kernel state.
	for _, method := range []string{http.MethodGet, http.MethodPut, http.MethodDelete} {
		t.Run(method, func(t *testing.T) {
			t.Parallel()
			req := httptest.NewRequest(method, "/api/v1/cache/drop", nil)
			w := httptest.NewRecorder()
			handleCacheDrop(w, req)

			res := w.Result()
			defer res.Body.Close()
			assert.Equal(t, http.StatusMethodNotAllowed, res.StatusCode)

			var body client.ErrorResponse
			require.NoError(t, json.NewDecoder(res.Body).Decode(&body))
			assert.Contains(t, body.Message, "POST")
		})
	}
}

func TestHandleCacheDropRejectsInvalidMode(t *testing.T) {
	t.Parallel()

	// Validated before any write is attempted, so this is safe to run in a unit
	// test: an invalid mode never reaches /proc/sys/vm/drop_caches.
	for _, mode := range []string{"0", "4", "abc"} {
		t.Run(mode, func(t *testing.T) {
			t.Parallel()
			req := httptest.NewRequest(http.MethodPost, "/api/v1/cache/drop?mode="+mode, nil)
			w := httptest.NewRecorder()
			handleCacheDrop(w, req)

			res := w.Result()
			defer res.Body.Close()
			assert.Equal(t, http.StatusBadRequest, res.StatusCode)

			var body client.ErrorResponse
			require.NoError(t, json.NewDecoder(res.Body).Decode(&body))
			assert.Contains(t, body.Message, "must be 1, 2 or 3")
		})
	}
}

func TestParseCacheStats(t *testing.T) {
	t.Parallel()

	// Trimmed sample of /proc/fs/fscache/stats. The interesting case is the one
	// observed in the field: cache writes climbing while cache reads stay at
	// zero, meaning the cache absorbs data but never serves it.
	const stats = `Reads  : DR=0 RA=9684543 RF=0 RS=0 WB=0 WBZ=0
Writes : BW=0 WT=0 DW=0 WP=0 2C=9684543
ZeroOps: ZR=0 sh=0 sk=0
DownOps: DL=12026307 ds=12026307 df=10 di=5
CaRdOps: RD=0 rs=0 rf=0
UpldOps: UL=0 us=0 uf=0
CaWrOps: WR=9684543 ws=9684543 wf=0
Retries: rq=0 rs=0 wq=0 ws=0
-- FS-Cache statistics --
Cookies: n=76 v=1 vcol=0 voom=0
`

	dir := t.TempDir()
	path := filepath.Join(dir, "stats")
	require.NoError(t, os.WriteFile(path, []byte(stats), 0o600))

	got, err := parseCacheStats(path)
	require.NoError(t, err)

	assert.Equal(t, uint64(12026307), got.DownOps.Downloads)
	assert.Equal(t, uint64(12026307), got.DownOps.Done)
	assert.Equal(t, uint64(10), got.DownOps.Failed)
	assert.Equal(t, uint64(5), got.DownOps.Instead)

	assert.Zero(t, got.CacheReads.Requests, "cache reads should be zero in this sample")
	assert.Zero(t, got.CacheReads.Done)
	assert.Zero(t, got.CacheReads.Failed)

	assert.Equal(t, uint64(9684543), got.CacheWrites.Requests)
	assert.Equal(t, uint64(9684543), got.CacheWrites.Done)
	assert.Zero(t, got.CacheWrites.Failed)
}

func TestParseCacheStatsHealthy(t *testing.T) {
	t.Parallel()

	// A working cache: reads served from cache, so CaRdOps is non-zero.
	const stats = `DownOps: DL=1000 ds=990 df=10 di=5
CaRdOps: RD=500 rs=490 rf=10
CaWrOps: WR=300 ws=295 wf=5
`

	path := filepath.Join(t.TempDir(), "stats")
	require.NoError(t, os.WriteFile(path, []byte(stats), 0o600))

	got, err := parseCacheStats(path)
	require.NoError(t, err)
	assert.Equal(t, uint64(500), got.CacheReads.Requests)
	assert.Equal(t, uint64(490), got.CacheReads.Done)
	assert.Equal(t, uint64(10), got.CacheReads.Failed)
}

func TestParseCacheStatsTolerance(t *testing.T) {
	t.Parallel()

	// Malformed and unknown lines must be skipped, not fatal, because the
	// counter set varies between kernel versions.
	const stats = `garbage without a colon
DownOps: DL=1000 ds=notanumber df=10 di=5
FutureOps: XX=1 YY=2
CaRdOps: RD=42 rs=40 rf=2
malformed=field: nokey
`

	path := filepath.Join(t.TempDir(), "stats")
	require.NoError(t, os.WriteFile(path, []byte(stats), 0o600))

	got, err := parseCacheStats(path)
	require.NoError(t, err)
	assert.Equal(t, uint64(1000), got.DownOps.Downloads)
	assert.Zero(t, got.DownOps.Done, "unparsable value should be skipped, leaving zero")
	assert.Equal(t, uint64(42), got.CacheReads.Requests)
}

func TestParseCacheStatsEmpty(t *testing.T) {
	t.Parallel()

	path := filepath.Join(t.TempDir(), "stats")
	require.NoError(t, os.WriteFile(path, nil, 0o600))

	got, err := parseCacheStats(path)
	require.NoError(t, err)
	assert.Zero(t, got.CacheReads.Requests)
}

func TestParseCacheStatsMissingFile(t *testing.T) {
	t.Parallel()

	// The counters only exist when the kernel has CONFIG_FSCACHE_STATS, so a
	// missing file must surface as an error rather than as zeroed counters that
	// would look like a broken cache.
	_, err := parseCacheStats(filepath.Join(t.TempDir(), "does-not-exist"))
	require.Error(t, err)
}
