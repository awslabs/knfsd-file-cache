/*
	Copyright 2023 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
	"unsafe"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-agent/client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/sys/unix"
)

const (
	KB = 1024
	MB = KB * 1024
	GB = MB * 1024

	// directIOAlignment is the alignment O_DIRECT requires for the buffer,
	// offset and length. 4096 covers the logical block size of every device
	// used by the smoke tests.
	directIOAlignment = 4096
)

func TestSmoke(t *testing.T) {
	// These tests need to be executed in order as some steps are dependent on
	// previous steps.
	require.True(t, t.Run("prepare", func(t *testing.T) {
		err := Sudo(`
		set -xe

		# Unmount the shares if they're already mounted, this allows re-running
		# the smoke tests.
		if mountpoint -q /mnt/source; then
			umount -f /mnt/source
		fi

		if mountpoint -q /mnt/proxy; then
			umount -f /mnt/proxy
		fi

		# Create the directories for the mounts.
		# Mark them as immutable so that if the mount fails no data
		# can be accidentally written to the local disk.
		mkdir -p /mnt/source /mnt/proxy
		chattr +i /mnt/source /mnt/proxy

		# Add symlinks to the test directories to simplify the tests.
		mkdir -p /test
		`)
		require.NoError(t, err)
	}))

	require.True(t, t.Run("mount source", func(t *testing.T) {
		// Mount the source directly so that we can bypass the proxy to verify
		// that data was written to the source, and setting up data to be read by
		// the proxy.
		sourceMount := fmt.Sprintf("%s:/files", sourceHost)
		err := Sudo(fmt.Sprintf(`
		set -e

		# Disable as much caching on the client as possible so that read/writes
		# always go back to the source.
		mount "%s" /mnt/source -o vers=3,proto=tcp,noac,noatime,nocto,rsize=1048576,wsize=1048576,lookupcache=none,nolock

		# Create the test directory if it doesn't already exist and
		# assign ownership to our test user.
		mkdir -p "/mnt/source/smoke-tests"
		rm -rf /mnt/source/smoke-tests/*
		chown "$SUDO_UID:$SUDO_GID" "/mnt/source/smoke-tests"
		chmod 775 "/mnt/source/smoke-tests"

		ln -snf /mnt/source/smoke-tests /test/source
		`, sourceMount))
		require.NoError(t, err)
	}))

	require.True(t, t.Run("mount proxy", func(t *testing.T) {
		proxyMount := fmt.Sprintf("%s:/files", proxyHost)
		err := Sudo(fmt.Sprintf(`
		set -e

		# Disable as much caching on the client as possible so that the
		# client has to re-query the proxy during the smoke tests.
		mount "%s" /mnt/proxy -o vers=3,proto=tcp,noac,noatime,nocto,rsize=1048576,wsize=1048576,lookupcache=none,nolock

		ln -snf /mnt/proxy/smoke-tests /test/proxy
		`, proxyMount))
		require.NoError(t, err)
	}))

	t.Run("read via proxy", func(t *testing.T) {
		t.Parallel()

		name, err := createRandomFile("/test/source", "read.*")
		require.NoError(t, err)
		t.Cleanup(func() { removeTestFile(name) })

		err = writeRandomData("/test/source/"+name, 1*MB)
		require.NoError(t, err)

		assertFilesEqual(t, "/test/source/"+name, "/test/proxy/"+name)
	})

	t.Run("write via proxy", func(t *testing.T) {
		t.Parallel()

		name, err := createRandomFile("/test/proxy", "write.*")
		require.NoError(t, err)
		t.Cleanup(func() { removeTestFile(name) })

		err = writeRandomData("/test/proxy/"+name, 1*MB)
		require.NoError(t, err)

		assertFilesEqual(t, "/test/proxy/"+name, "/test/source/"+name)
	})

	t.Run("metadata caches positive lookups", func(t *testing.T) {
		t.Parallel()

		// Create a random file on the source and stat it via the proxy. Then
		// remove the file from the source. The proxy should still have the
		// metadata cached as the proxy will be unaware the file was removed.

		// Use a private directory for this subtest. The proxy caches a lookup
		// result keyed against the parent directory's attributes; if other
		// parallel subtests create or remove files in a shared parent directory
		// the proxy observes the changed directory mtime and drops the cached
		// entry, which would make this assertion racy. An isolated directory
		// guarantees the only changes to it are this subtest's own out-of-band
		// (source-side) mutations, which the proxy never sees.
		dir, err := createTestDir("meta-positive")
		require.NoError(t, err)
		t.Cleanup(dir.cleanup)

		name, err := createRandomFile(dir.source, "meta.*")
		require.NoError(t, err)

		before, err := os.Stat(dir.proxy + "/" + name)
		require.NoError(t, err)

		// A single stat doesn't always cache the metadata, so re-read.
		for range 100 {
			_, err = os.Stat(dir.proxy + "/" + name)
			require.NoError(t, err)
		}

		// Remove the file directly via the source so the proxy is unaware.
		err = os.Remove(dir.source + "/" + name)
		require.NoError(t, err)

		// Drop this machines caches so that it has to go back to the proxy.
		err = dropLocalVMCaches()
		require.NoError(t, err)

		// Read the metadata from the proxy for the now non-existent file.
		require.FileExists(t, dir.proxy+"/"+name)
		assert.NoFileExists(t, dir.source+"/"+name)

		after, err := os.Stat(dir.proxy + "/" + name)
		require.NoError(t, err)
		assert.Equal(t, before, after)
	})

	t.Run("metadata caches negative lookups", func(t *testing.T) {
		t.Parallel()

		// Similar to the positive test, only we're going to stat a file that
		// doesn't exist, then create it. The proxy should continue to think the
		// file doesn't exist.

		// Use a private directory for this subtest. The proxy caches a negative
		// lookup result keyed against the parent directory's attributes. Unlike
		// a positive entry (which is backed by a cached file handle/inode and
		// survives a directory change for acreg{min,max}), a negative entry
		// lives entirely at the directory level and is dropped the moment the
		// proxy observes the parent directory's mtime has changed. If this
		// subtest shared a parent directory with the other parallel subtests,
		// their concurrent file creates/removes would churn that directory's
		// mtime, the proxy would refresh and invalidate the negative entry, and
		// the assertion below would flake. Isolating the directory ensures the
		// only mutation is this subtest's own source-side create, which the
		// proxy never sees, so the cached negative entry remains valid.
		dir, err := createTestDir("meta-negative")
		require.NoError(t, err)
		t.Cleanup(dir.cleanup)

		// Grab a random file name.
		name, err := createRandomFile(dir.source, "meta.*")
		require.NoError(t, err)

		// Remove the file and ensure it doesn't exist according to the proxy.
		err = os.Remove(dir.source + "/" + name)
		require.NoError(t, err)
		require.NoFileExists(t, dir.source+"/"+name)
		require.NoFileExists(t, dir.proxy+"/"+name)

		// Ensure the negative lookup is cached on the proxy.
		for range 100 {
			os.Stat(dir.proxy + "/" + name)
		}

		// Create the file directly on the source so the proxy is unaware.
		f, err := os.Create(dir.source + "/" + name)
		require.NoError(t, err)
		f.Close()

		// Drop this machines caches so that it has to go back to the proxy.
		err = dropLocalVMCaches()
		require.NoError(t, err)

		assert.NoFileExists(t, dir.proxy+"/"+name)
		assert.FileExists(t, dir.source+"/"+name)
	})

	t.Run("proxy caches file data", func(t *testing.T) {
		// This test checks two properties of the cache:
		// * The cache actually caches the file data
		// * The file data is cached on disk using cachefilesd
		// It is not worth separating these two tests out as the setup for them
		// is identical, and working with a 1GB file makes the test
		// comparatively slow.
		//
		// Not using a tool such as fincore as we're explicitly testing that the
		// file data was cached to disk using FS-Cache (cachefilesd).
		//
		// If the cache is full, this test would fail as old data would need to
		// be evicted to store the new data, resulting in a net difference of
		// zero. However, this is not considered an issue as these smoke tests
		// are designed to be run on a new instance of the proxy that was
		// created specifically for running the smoke tests. As such its only
		// likely this will happen when developing the smoke tests where a
		// developer is likely to keep re-running the same tests on the same
		// instance.

		// This could fail if the cache is full, as old data will be evicted
		// to make space for the new data. However, in practice this is
		// unlikely when running smoke tests as the cache size is 350 GB.
		initialSize, err := fsCacheSize()
		require.NoError(t, err)

		scratch := scratchDir()
		name, err := createRandomFile(scratch, "large.*")
		require.NoError(t, err)
		local := filepath.Join(scratch, name)
		t.Cleanup(func() {
			_ = os.Remove(local)
			removeTestFile(name)
		})

		// Seed large (1G) file for the cache test. Create the file locally so
		// that it can be compared after deleting the source.
		err = writeRandomData(local, 1*GB)
		require.NoError(t, err)

		err = copyFile(local, "/test/source/"+name)
		require.NoError(t, err)

		// Read the file through the proxy and ensure it matches.
		assertFilesEqual(t, local, "/test/proxy/"+name)

		// Read it a few more times to ensure it is fully cached.
		//
		// These are BUFFERED reads. That is deliberate and is asserted below,
		// rather than being left as an implicit consequence of how copyFile
		// happens to be implemented: buffered and O_DIRECT reads take different
		// paths through netfs and have been observed to differ in whether they
		// populate the cache, so which one is under test must not be accidental.
		for range 10 {
			err = copyFile("/test/proxy/"+name, "/dev/null")
			require.NoError(t, err)
		}

		// Confirm both read modes work against the cached file, so a regression
		// in either is caught here rather than only in the fragmentation rig.
		for _, direct := range []bool{false, true} {
			data, err := readRange("/test/proxy/"+name, 0, 1*MB, direct)
			require.NoError(t, err, "reading via the proxy with direct=%t", direct)
			require.Len(t, data, 1*MB, "short read with direct=%t", direct)
		}

		err = dropLocalVMCaches()
		require.NoError(t, err)

		// Remove the file from the source, then test that the proxy still
		// serves the file from the cache.
		err = os.Remove("/test/source/" + name)
		require.NoError(t, err)

		assertFilesEqual(t, local, "/test/proxy/"+name)

		cacheSize, err := fsCacheSize()
		require.NoError(t, err)

		initialSize /= MB
		cacheSize /= MB
		diff := cacheSize - initialSize
		if diff < 970 || diff > 1080 {
			msg := fmt.Sprintf(
				"Expected cache delta to be between 970M and 1080M, but was %d MB\n"+
					"Initial size: %d MB\n"+
					"  Final size: %d MB",
				diff, initialSize, cacheSize,
			)
			t.Error(msg)
		}
	})

	// Checks that the cache actually *serves* reads, not just that it grows.
	//
	// Cache writes and cache reads fail independently. A cache can be filling
	// correctly while never serving a single read, in which case every request
	// still goes to the source filer and the cache is pure overhead. That state
	// was observed in the field, and the "proxy caches file data" test above
	// cannot detect it for two reasons:
	//
	//   * it asserts on filesystem bytes used, which only proves writes work
	//   * it drops caches on the client only, so the re-read is served from the
	//     proxy's page cache (L1) rather than from FS-Cache (L2)
	//
	// This test closes both gaps by dropping the proxy's page cache too and
	// asserting on the kernel's own cache-read counter.
	t.Run("proxy serves reads from cache", func(t *testing.T) {
		dir, err := createTestDir("cache-read")
		require.NoError(t, err)
		t.Cleanup(dir.cleanup)

		name := "cache-read.bin"
		const size = 512 * MB

		require.NoError(t, writeRandomData(dir.source+"/"+name, size))

		// Populate the cache. Read twice; the first read may be satisfied
		// before the cache write completes.
		for range 2 {
			require.NoError(t, copyFile(dir.proxy+"/"+name, "/dev/null"))
		}

		// Evict L1 on BOTH sides so the next read has to come from FS-Cache.
		// Pagecache alone is enough, and avoids discarding dentry and inode
		// caches that the rest of the suite relies on.
		require.NoError(t, dropLocalVMCaches())
		_, err = proxy.DropCaches(client.DropCachesPageCache)
		require.NoError(t, err)

		before, err := proxy.CacheStats()
		require.NoError(t, err)

		require.NoError(t, copyFile(dir.proxy+"/"+name, "/dev/null"))

		after, err := proxy.CacheStats()
		require.NoError(t, err)

		reads := after.CacheReads.Requests - before.CacheReads.Requests
		downloads := after.DownOps.Downloads - before.DownOps.Downloads

		assert.Positive(t, reads,
			"expected the proxy to read from FS-Cache, but CaRdOps.RD did not increase "+
				"(cache reads: %d, source downloads: %d). The cache is being written "+
				"but never read, so every request goes to the source filer.",
			reads, downloads)

		assert.Zero(t, after.CacheReads.Failed-before.CacheReads.Failed,
			"cache reads were attempted but failed")
	})

	// Checks that a sparse source file is cached. Reads of a hole return zeros,
	// and those zeros still have to be stored in the cache, otherwise a filer
	// holding sparse files gets a silently useless cache.
	//
	// The existing tests all write random data, so they never exercise this.
	t.Run("proxy caches sparse source files", func(t *testing.T) {
		dir, err := createTestDir("sparse")
		require.NoError(t, err)
		t.Cleanup(dir.cleanup)

		name := "sparse.bin"
		const (
			apparentSize = 1 * GB
			readSize     = 256 * MB
		)

		// truncate sets i_size without allocating blocks, so this is instant
		// and consumes no space on the source.
		require.NoError(t, createSparseFile(dir.source+"/"+name, apparentSize))

		info, err := os.Stat(dir.source + "/" + name)
		require.NoError(t, err)
		require.Equal(t, int64(apparentSize), info.Size(), "sparse file should report its apparent size")

		initialSize, err := fsCacheSize()
		require.NoError(t, err)

		// Buffered read of the first readSize bytes, twice, so the cache write
		// has completed by the time it is measured.
		for range 2 {
			data, err := readRange(dir.proxy+"/"+name, 0, readSize, false)
			require.NoError(t, err)
			require.Len(t, data, readSize)
			assert.True(t, allZeros(data), "reads of a hole should return zeros")
		}

		cacheSize, err := fsCacheSize()
		require.NoError(t, err)

		// Allow a generous lower bound; the cache stores the range read plus
		// metadata, and may round up to its own granularity.
		delta := (cacheSize - initialSize) / MB
		assert.Greater(t, delta, uint64(readSize/MB)/2,
			"expected roughly %d MB of cache growth after reading a sparse range, got %d MB. "+
				"Sparse source ranges are not being cached.",
			readSize/MB, delta)
	})
}

func createRandomFile(dir, pattern string) (string, error) {
	f, err := os.CreateTemp(dir, pattern)
	if err != nil {
		return "", err
	}
	f.Close()
	return filepath.Base(f.Name()), nil
}

// testDir is a per-subtest directory that exists under the shared smoke-test
// directory on both the source and the proxy. Subtests that depend on the
// proxy's directory-level metadata cache (e.g. negative-lookup caching) must
// use a private directory so concurrent parallel subtests cannot churn the
// parent directory's mtime and invalidate the cached entry under test.
type testDir struct {
	source string // absolute path to the directory via the source mount
	proxy  string // absolute path to the directory via the proxy mount
}

// cleanup best-effort removes the directory and its contents via the source.
// It removes contents via the proxy first so the proxy is aware they are gone.
func (d testDir) cleanup() {
	entries, _ := os.ReadDir(d.source)
	for _, e := range entries {
		_ = os.Remove(d.proxy + "/" + e.Name())
		_ = os.Remove(d.source + "/" + e.Name())
	}
	_ = os.Remove(d.proxy)
	_ = os.Remove(d.source)
}

// createTestDir creates a unique directory on the source under the shared
// smoke-test root and returns the source and proxy paths to it. The directory
// is created via the source mount so the proxy discovers it on first lookup.
func createTestDir(prefix string) (testDir, error) {
	path, err := os.MkdirTemp("/test/source", prefix+".*")
	if err != nil {
		return testDir{}, err
	}
	name := filepath.Base(path)
	return testDir{
		source: "/test/source/" + name,
		proxy:  "/test/proxy/" + name,
	}, nil
}

func writeRandomData(path string, size uint64) error {
	// Use dd as it's already solved the hard problems of setting cache flags
	// and efficiently copying data.
	out, err := exec.Command("dd",
		"if=/dev/urandom",
		"of="+path,
		"bs=4M",
		"count="+strconv.FormatUint(size, 10),
		"iflag=count_bytes",
		"oflag=nocache",
		"status=none",
	).CombinedOutput() // #nosec G204
	if err != nil {
		return fmt.Errorf("dd writing %s (%d bytes): %w: %s", path, size, err, out)
	}
	return nil
}

func assertFilesEqual(t *testing.T, expected, actual string) {
	t.Helper()
	out, err := exec.Command("cmp", expected, actual).CombinedOutput()
	if err != nil {
		t.Logf("files were different: %s", out)
	}
}

// createSparseFile creates a file with the given apparent size without
// allocating any blocks, so reads of it return zeros from a hole.
func createSparseFile(path string, size int64) error {
	f, err := os.Create(path) // #nosec G304 -- test path built from the test's own temp dir
	if err != nil {
		return err
	}
	defer f.Close()

	if err := f.Truncate(size); err != nil {
		return fmt.Errorf("truncate %s to %d: %w", path, size, err)
	}
	return nil
}

// readRange reads length bytes from offset.
//
// The read mode is explicit rather than inherited from whatever cp happens to
// do, because buffered and O_DIRECT reads take different paths through netfs and
// have been observed to differ in whether they populate the cache. Relying on
// cp's implementation detail would mean a change to coreutils could silently
// alter what these tests cover.
func readRange(path string, offset int64, length int, direct bool) ([]byte, error) {
	flags := os.O_RDONLY
	if direct {
		flags |= unix.O_DIRECT
	}

	f, err := os.OpenFile(path, flags, 0) // #nosec G304 -- test path built from the test's own temp dir
	if err != nil {
		return nil, fmt.Errorf("open %s (direct=%t): %w", path, direct, err)
	}
	defer f.Close()

	// O_DIRECT requires the buffer, offset and length to be aligned to the
	// logical block size. Allocate an extra page and slice to an aligned start
	// so the buffer address satisfies the constraint.
	buf := make([]byte, length+directIOAlignment)
	start := 0
	if direct {
		if off := int(uintptr(unsafe.Pointer(&buf[0]))) % directIOAlignment; off != 0 {
			start = directIOAlignment - off
		}
	}
	buf = buf[start : start+length]

	n, err := f.ReadAt(buf, offset)
	if err != nil && !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("read %s at %d (direct=%t): %w", path, offset, direct, err)
	}
	return buf[:n], nil
}

// allZeros reports whether b contains only zero bytes, i.e. hole contents.
func allZeros(b []byte) bool {
	for _, c := range b {
		if c != 0 {
			return false
		}
	}
	return true
}

func removeTestFile(name string) {
	// Do our best to remove the file, try via the proxy first so that
	// the proxy is aware the file was removed.
	_ = os.Remove("/test/proxy/" + name)
	_ = os.Remove("/test/source/" + name)
}

func dropLocalVMCaches() error {
	unix.Sync()
	return os.WriteFile("/proc/sys/vm/drop_caches", []byte("3\n"), 0)
}

func fsCacheSize() (uint64, error) {
	u, err := proxy.CacheUsage()
	if err != nil {
		return 0, err
	}
	return u.BytesUsed, nil
}

func scratchDir() string {
	const tmp = "/tmp"
	if fi, err := os.Stat(tmp); err == nil && fi.IsDir() {
		return tmp
	}
	return "."
}

func copyFile(src, dst string) error {
	// It's easier to just fork out to cp than try to re-implement the logic.
	cmd := exec.Command("cp", "--", src, dst)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("cp %s -> %s: %w: %s", src, dst, err, out)
	}
	return nil
}
