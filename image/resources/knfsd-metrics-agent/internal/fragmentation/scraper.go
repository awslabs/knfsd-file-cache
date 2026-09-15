/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fragmentation

import (
	"context"
	"io/fs"
	"math"
	"os"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/fragmentation/internal/metadata"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
	"golang.org/x/sys/unix"
)

// fsIocFiemap is FS_IOC_FIEMAP, which is _IOWR('f', 11, struct fiemap) and
// resolves to 0xc020660b on Linux for the 32 byte struct fiemap defined in
// <linux/fiemap.h>.
const fsIocFiemap = 0xc020660b

// fiemapMaxOffset mirrors FIEMAP_MAX_OFFSET from <linux/fiemap.h>.
const fiemapMaxOffset = ^uint64(0)

// Flags from <linux/fiemap.h>.
//
// fiemapExtentUnwritten marks space that XFS has allocated but which holds no
// data. The extent size hint pads each allocation up to the hint, and that
// padding is reported as unwritten, so summing these lengths yields exactly the
// capacity consumed by the hint.
const (
	fiemapExtentLast      = 0x00000001
	fiemapExtentUnwritten = 0x00000800
)

// fiemapExtentBatch is how many extent records to request per ioctl. Each
// record is 56 bytes, so this caps the copy at 56 KiB per call.
const fiemapExtentBatch = 1024

// walkInterval is how many directory entries to process between context
// cancellation checks. Checking the context requires locking a mutex, so it is
// not done for every entry.
const walkInterval = 100

// fiemap mirrors struct fiemap from <linux/fiemap.h>. The trailing
// fm_extents[] array is supplied separately, immediately after this header in
// the same buffer.
type fiemap struct {
	fmStart         uint64
	fmLength        uint64
	fmFlags         uint32
	fmMappedExtents uint32
	fmExtentCount   uint32
	fmReserved      uint32
}

// fiemapExtent mirrors struct fiemap_extent from <linux/fiemap.h>. The struct
// is 56 bytes: three u64 public fields, two reserved u64, one u32 of flags,
// then three reserved u32.
type fiemapExtent struct {
	feLogical    uint64
	fePhysical   uint64
	feLength     uint64
	feReserved64 [2]uint64
	feFlags      uint32
	feReserved   [3]uint32
}

// extentInfo is the per-file result of a FIEMAP walk.
type extentInfo struct {
	extents        int64
	writtenBytes   int64
	unwrittenBytes int64
}

type fragmentationScraper struct {
	mb          *metadata.MetricsBuilder
	logger      *zap.Logger
	cachePath   string
	minFileSize int64
}

// stats holds the aggregate collected during a single walk of the cache.
type stats struct {
	files          int64
	extents        int64
	maxExtents     int64
	allocatedBytes int64
	apparentBytes  int64
	writtenBytes   int64
	unwrittenBytes int64
}

func newScraper(
	mb *metadata.MetricsBuilder,
	logger *zap.Logger,
	cachePath string,
	minFileSize int64,
) (scraper.Metrics, error) {
	s := &fragmentationScraper{
		mb:          mb,
		logger:      logger,
		cachePath:   cachePath,
		minFileSize: minFileSize,
	}
	return scraper.NewMetrics(s.scrape)
}

func (s *fragmentationScraper) scrape(ctx context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping FS-Cache fragmentation", zap.String("cache_path", s.cachePath))

	start := time.Now()
	collected, err := s.collect(ctx)
	elapsed := time.Since(start)

	if err != nil {
		// Return empty metrics rather than an error to avoid stopping the
		// collector. A missing cache path is normal when FS-Cache is not in
		// use, and a cancelled context means the scrape timed out.
		s.logger.Warn("failed to collect FS-Cache fragmentation statistics", zap.Error(err))
		return pmetric.NewMetrics(), nil
	}

	now := pcommon.NewTimestampFromTime(time.Now())

	// Only report extent statistics when at least one file was measured,
	// otherwise an empty cache would publish a misleading mean of zero.
	if collected.files > 0 && collected.extents > 0 {
		s.mb.RecordFscacheExtentsMeanBytesDataPoint(now, collected.allocatedBytes/collected.extents)
		s.mb.RecordFscacheExtentsMaxDataPoint(now, collected.maxExtents)
	}

	// Capacity held in unwritten extents: allocated by the XFS extent size
	// hint but not yet holding cached data. Consumed as backing files fill,
	// and zero when the hint is disabled.
	s.mb.RecordFscacheExtentsUnwrittenBytesDataPoint(now, collected.unwrittenBytes)

	s.mb.RecordFscacheFragmentationScrapeDurationDataPoint(now, elapsed.Milliseconds())

	s.logger.Debug("Scraped FS-Cache fragmentation",
		zap.Int64("files", collected.files),
		zap.Int64("extents", collected.extents),
		zap.Int64("max_extents", collected.maxExtents),
		zap.Int64("unwritten_bytes", collected.unwrittenBytes),
		zap.Duration("duration", elapsed))

	return s.mb.Emit(), nil
}

// collect walks the cache and aggregates extent statistics for every regular
// file at or above the configured minimum size.
func (s *fragmentationScraper) collect(ctx context.Context) (stats, error) {
	var collected stats

	if _, err := os.Stat(s.cachePath); err != nil {
		return collected, err
	}

	count := 0
	err := filepath.WalkDir(s.cachePath, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			// Skip entries that cannot be read. The cache changes constantly
			// underneath the walk, so this is expected.
			return nil
		}

		count++
		if count > walkInterval {
			count = 0
			if err := ctx.Err(); err != nil {
				// abort walking the tree with the context's error
				return err
			}
		}

		if !d.Type().IsRegular() {
			return nil
		}

		info, errFile := d.Info()
		if errFile != nil {
			return nil
		}

		if info.Size() < s.minFileSize {
			return nil
		}

		extents, errExtents := mapExtents(path)
		if errExtents != nil {
			return nil
		}

		collected.files++
		collected.extents += extents.extents
		if extents.extents > collected.maxExtents {
			collected.maxExtents = extents.extents
		}
		collected.writtenBytes += extents.writtenBytes
		collected.unwrittenBytes += extents.unwrittenBytes

		// st_blocks is always in 512 byte units regardless of the filesystem
		// block size, and counts blocks actually allocated, so it captures any
		// extent size hint padding.
		if st, ok := info.Sys().(*syscall.Stat_t); ok {
			collected.allocatedBytes += st.Blocks * 512
		}
		collected.apparentBytes += info.Size()

		return nil
	})
	if err != nil {
		return stats{}, err
	}

	return collected, nil
}

// mapExtents walks a file's extent map with the FIEMAP ioctl, returning the
// extent count and the split between written and unwritten bytes.
//
// The unwritten total is the useful part: XFS pads each allocation up to the
// extent size hint and reports that padding as unwritten, so this yields
// exactly the capacity the hint is consuming without holding cached data.
//
// Records are retrieved in batches rather than one ioctl per extent, so a file
// with hundreds of thousands of extents costs only a handful of calls.
func mapExtents(path string) (extentInfo, error) {
	var info extentInfo

	f, err := os.Open(path) // #nosec G304 -- path is produced by walking the configured cache directory
	if err != nil {
		return info, err
	}
	defer f.Close()

	// A single buffer holding the fiemap header followed by fiemapExtentBatch
	// extent records, which is the layout the ioctl expects.

	// nosemgrep: use-of-unsafe-block
	hdrSize := int(unsafe.Sizeof(fiemap{}))
	// nosemgrep: use-of-unsafe-block
	extSize := int(unsafe.Sizeof(fiemapExtent{}))
	buf := make([]byte, hdrSize+extSize*fiemapExtentBatch)

	var start uint64
	for {
		// nosemgrep: use-of-unsafe-block
		hdr := (*fiemap)(unsafe.Pointer(&buf[0])) // #nosec G103 -- required to lay the struct over the ioctl buffer
		hdr.fmStart = start
		hdr.fmLength = fiemapMaxOffset
		hdr.fmFlags = 0
		hdr.fmMappedExtents = 0
		hdr.fmExtentCount = fiemapExtentBatch

		_, _, errno := unix.Syscall(
			unix.SYS_IOCTL,
			f.Fd(),
			uintptr(fsIocFiemap),
			// nosemgrep: use-of-unsafe-block
			uintptr(unsafe.Pointer(&buf[0])), // #nosec G103 -- required to pass the struct to the FIEMAP ioctl
		)
		if errno != 0 {
			return extentInfo{}, errno
		}

		mapped := int(hdr.fmMappedExtents)
		if mapped == 0 {
			return info, nil
		}

		var last bool
		var next uint64
		for i := range mapped {
			off := hdrSize + i*extSize
			// nosemgrep: use-of-unsafe-block
			ext := (*fiemapExtent)(unsafe.Pointer(&buf[off])) // #nosec G103 -- required to read the ioctl result

			info.extents++
			// Extent lengths are bounded by the file size, so they cannot
			// realistically exceed the int64 range. Clamp defensively rather
			// than trusting a value that came from an ioctl.
			length := min(ext.feLength, math.MaxInt64)
			if ext.feFlags&fiemapExtentUnwritten != 0 {
				info.unwrittenBytes += int64(length)
			} else {
				info.writtenBytes += int64(length)
			}

			next = ext.feLogical + ext.feLength
			if ext.feFlags&fiemapExtentLast != 0 {
				last = true
			}
		}

		if last {
			return info, nil
		}
		start = next
	}
}
