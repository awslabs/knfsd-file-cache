/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fragmentation

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

// writeFile creates a file of the given size filled with a repeating byte.
func writeFile(t *testing.T, path string, size int) {
	t.Helper()
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o750))
	data := make([]byte, size)
	for i := range data {
		data[i] = 0xa5
	}
	require.NoError(t, os.WriteFile(path, data, 0o600))
}

func newTestScraper(cachePath string, minFileSize int64) *fragmentationScraper {
	return &fragmentationScraper{
		logger:      zap.NewNop(),
		cachePath:   cachePath,
		minFileSize: minFileSize,
	}
}

func TestMapExtents(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "file")
	writeFile(t, path, 1024*1024)

	info, err := mapExtents(path)
	require.NoError(t, err)

	// A freshly written 1 MiB file occupies at least one extent. The exact
	// count depends on the filesystem backing the test temp dir, so only
	// assert the values are sane rather than exact figures.
	assert.GreaterOrEqual(t, info.extents, int64(1))
	assert.Positive(t, info.writtenBytes)

	// Without an extent size hint there is no padding, so nothing should be
	// reported as unwritten.
	assert.Equal(t, int64(0), info.unwrittenBytes)
}

func TestMapExtentsBatching(t *testing.T) {
	t.Parallel()

	// A file large enough to need more than one ioctl would require a very
	// fragmented layout, which cannot be forced portably. Instead assert the
	// batch loop terminates and reports a consistent total for a plain file.
	dir := t.TempDir()
	path := filepath.Join(dir, "big")
	writeFile(t, path, 8*1024*1024)

	info, err := mapExtents(path)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, info.extents, int64(1))
	assert.Equal(t, int64(8*1024*1024), info.writtenBytes+info.unwrittenBytes)
}

func TestMapExtentsEmptyFile(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "empty")
	writeFile(t, path, 0)

	info, err := mapExtents(path)
	require.NoError(t, err)
	assert.Equal(t, int64(0), info.extents)
	assert.Equal(t, int64(0), info.writtenBytes)
	assert.Equal(t, int64(0), info.unwrittenBytes)
}

func TestMapExtentsMissingFile(t *testing.T) {
	t.Parallel()

	_, err := mapExtents(filepath.Join(t.TempDir(), "does-not-exist"))
	assert.Error(t, err)
}

func TestCollect(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "cache", "@c1", "big1"), 2*1024*1024)
	writeFile(t, filepath.Join(dir, "cache", "@c1", "big2"), 2*1024*1024)

	s := newTestScraper(dir, 1024*1024)
	collected, err := s.collect(context.Background())
	require.NoError(t, err)

	assert.Equal(t, int64(2), collected.files)
	assert.GreaterOrEqual(t, collected.extents, int64(2))
	assert.GreaterOrEqual(t, collected.maxExtents, int64(1))
	assert.Equal(t, int64(4*1024*1024), collected.apparentBytes)
	assert.Positive(t, collected.allocatedBytes)
	assert.Positive(t, collected.writtenBytes)

	// No extent size hint on the test filesystem, so no wasted capacity.
	assert.Equal(t, int64(0), collected.unwrittenBytes)
}

func TestCollectSkipsSmallFiles(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "small"), 8*1024)
	writeFile(t, filepath.Join(dir, "big"), 2*1024*1024)

	s := newTestScraper(dir, 1024*1024)
	collected, err := s.collect(context.Background())
	require.NoError(t, err)

	assert.Equal(t, int64(1), collected.files)
	assert.Equal(t, int64(2*1024*1024), collected.apparentBytes)
}

func TestCollectIncludesSmallFilesWhenMinSizeZero(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "small"), 8*1024)
	writeFile(t, filepath.Join(dir, "big"), 2*1024*1024)

	s := newTestScraper(dir, 0)
	collected, err := s.collect(context.Background())
	require.NoError(t, err)

	assert.Equal(t, int64(2), collected.files)
}

func TestCollectSkipsNonRegularFiles(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "big"), 2*1024*1024)
	require.NoError(t, os.MkdirAll(filepath.Join(dir, "subdir"), 0o750))
	require.NoError(t, os.Symlink(filepath.Join(dir, "big"), filepath.Join(dir, "link")))

	s := newTestScraper(dir, 1024*1024)
	collected, err := s.collect(context.Background())
	require.NoError(t, err)

	// only the regular file is counted, not the directory or the symlink
	assert.Equal(t, int64(1), collected.files)
}

func TestCollectEmptyCache(t *testing.T) {
	t.Parallel()

	s := newTestScraper(t.TempDir(), 1024*1024)
	collected, err := s.collect(context.Background())
	require.NoError(t, err)

	assert.Equal(t, int64(0), collected.files)
	assert.Equal(t, int64(0), collected.extents)
	assert.Equal(t, int64(0), collected.apparentBytes)
}

func TestCollectMissingCachePath(t *testing.T) {
	t.Parallel()

	// A missing cache path must surface as an error so that scrape() can
	// return empty metrics rather than stopping the collector.
	s := newTestScraper(filepath.Join(t.TempDir(), "does-not-exist"), 1024*1024)
	_, err := s.collect(context.Background())
	assert.Error(t, err)
}

func TestCollectCancelledContext(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	// enough entries to cross the walkInterval context check
	for i := range walkInterval * 2 {
		writeFile(t, filepath.Join(dir, fmt.Sprintf("f%04d", i)), 0)
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	s := newTestScraper(dir, 0)
	_, err := s.collect(ctx)
	assert.ErrorIs(t, err, context.Canceled)
}
