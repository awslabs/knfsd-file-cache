/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fscache

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/convert"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/fscache/internal/metadata"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
)

// fscacheStats holds all parsed statistics from /proc/fs/fscache/stats
type fscacheStats struct {
	// Netfslib statistics
	Reads   readsStats
	Writes  writesStats
	ZeroOps zeroOpsStats
	DownOps downOpsStats
	CaRdOps caRdOpsStats
	UpldOps upldOpsStats
	CaWrOps caWrOpsStats
	Retries retriesStats
	Objs    objsStats
	WbLock  wbLockStats

	// FS-Cache statistics
	Cookies cookiesStats
	Acquire acquireStats
	LRU     lruStats
	Invals  invalsStats
	Updates updatesStats
	Relinqs relinqsStats
	NoSpace noSpaceStats
	IO      ioStats
}

type readsStats struct {
	DR  uint64 // Direct Read
	RA  uint64 // Readahead
	RF  uint64 // Read Folio
	RS  uint64 // Read Single
	WB  uint64 // Write Begin
	WBZ uint64 // Write Zero Skip
}

type writesStats struct {
	BW uint64 // Buffered Write
	WT uint64 // Write Through
	DW uint64 // Direct Write
	WP uint64 // Write Pages
	C2 uint64 // Copy to Cache (2C)
}

type zeroOpsStats struct {
	ZR uint64 // Zero Read
	Sh uint64 // Short Read
	Sk uint64 // Skip
}

type downOpsStats struct {
	DL uint64 // Download
	Ds uint64 // Download Done
	Df uint64 // Download Failed
	Di uint64 // Download Instead
}

type caRdOpsStats struct {
	RD uint64 // Cache Read
	Rs uint64 // Cache Read Done
	Rf uint64 // Cache Read Failed
}

type upldOpsStats struct {
	UL uint64 // Upload
	Us uint64 // Upload Done
	Uf uint64 // Upload Failed
}

type caWrOpsStats struct {
	WR uint64 // Cache Write
	Ws uint64 // Cache Write Done
	Wf uint64 // Cache Write Failed
}

type retriesStats struct {
	Rq uint64 // Read Request Retries
	Rs uint64 // Read Subrequest Retries
	Wq uint64 // Write Request Retries
	Ws uint64 // Write Subrequest Retries
}

type objsStats struct {
	Rr  uint64 // Read Requests
	Sr  uint64 // Subrequests
	Foq uint64 // Folio Queue
	Wsc uint64 // Write Stream Conflicts
}

type wbLockStats struct {
	Skip uint64 // Writeback Lock Skip
	Wait uint64 // Writeback Lock Wait
}

type cookiesStats struct {
	N    uint64 // Data storage cookies
	V    uint64 // Volume index cookies
	Vcol uint64 // Volume collisions
	Voom uint64 // Volume OOM
}

type acquireStats struct {
	N   uint64 // Acquire requests
	Ok  uint64 // Acquire OK
	Oom uint64 // Acquire OOM
}

type lruStats struct {
	N   uint64 // LRU count
	Exp uint64 // Expired
	Rmv uint64 // Removed
	Drp uint64 // Dropped
	// At is not scraped (time till next cull in jiffies - not useful for monitoring)
}

type invalsStats struct {
	N uint64 // Invalidations
}

type updatesStats struct {
	N   uint64 // Update requests
	Rsz uint64 // Resize
	Rsn uint64 // Resize Skipped
}

type relinqsStats struct {
	N    uint64 // Relinquish requests
	Rtr  uint64 // Retire
	Drop uint64 // Drop
}

type noSpaceStats struct {
	Nwr  uint64 // Write refused
	Ncr  uint64 // Create refused
	Cull uint64 // Objects culled
}

type ioStats struct {
	Rd  uint64 // Read operations
	Wr  uint64 // Write operations
	Mis uint64 // DIO misfit
}

type fscacheScraper struct {
	mb        *metadata.MetricsBuilder
	logger    *zap.Logger
	statsPath string
}

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger, statsPath string) (scraper.Metrics, error) {
	s := &fscacheScraper{
		mb:        mb,
		logger:    logger,
		statsPath: statsPath,
	}
	return scraper.NewMetrics(s.scrape)
}

func (s *fscacheScraper) scrape(ctx context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping fscache metrics")

	now := pcommon.NewTimestampFromTime(time.Now())

	stats, err := parseFscacheStats(s.statsPath)
	if err != nil {
		s.logger.Warn("Failed to scrape fscache stats", zap.Error(err))
		// Return empty metrics rather than error to avoid stopping the collector
		return s.mb.Emit(), nil
	}

	// Record Netfslib metrics
	s.recordNetfsMetrics(now, stats)

	// Record FS-Cache metrics
	s.recordFscacheMetrics(now, stats)

	metrics := s.mb.Emit()

	s.logger.Debug("Emitting metrics",
		zap.Int("MetricCount", metrics.MetricCount()),
		zap.Int("DataPointCount", metrics.DataPointCount()))

	return metrics, nil
}

func (s *fscacheScraper) recordNetfsMetrics(now pcommon.Timestamp, stats *fscacheStats) {
	// Reads
	s.mb.RecordNetfsReadsDirectDataPoint(now, convert.Int64(stats.Reads.DR))
	s.mb.RecordNetfsReadsReadaheadDataPoint(now, convert.Int64(stats.Reads.RA))
	s.mb.RecordNetfsReadsFolioDataPoint(now, convert.Int64(stats.Reads.RF))
	s.mb.RecordNetfsReadsSingleDataPoint(now, convert.Int64(stats.Reads.RS))
	s.mb.RecordNetfsReadsWriteBeginDataPoint(now, convert.Int64(stats.Reads.WB))
	s.mb.RecordNetfsReadsWriteZskipDataPoint(now, convert.Int64(stats.Reads.WBZ))

	// Writes
	s.mb.RecordNetfsWritesBufferedDataPoint(now, convert.Int64(stats.Writes.BW))
	s.mb.RecordNetfsWritesWritethroughDataPoint(now, convert.Int64(stats.Writes.WT))
	s.mb.RecordNetfsWritesDirectDataPoint(now, convert.Int64(stats.Writes.DW))
	s.mb.RecordNetfsWritesPagesDataPoint(now, convert.Int64(stats.Writes.WP))
	s.mb.RecordNetfsWritesCopyToCacheDataPoint(now, convert.Int64(stats.Writes.C2))

	// ZeroOps
	s.mb.RecordNetfsZeroOpsZeroDataPoint(now, convert.Int64(stats.ZeroOps.ZR))
	s.mb.RecordNetfsZeroOpsShortDataPoint(now, convert.Int64(stats.ZeroOps.Sh))
	s.mb.RecordNetfsZeroOpsSkipDataPoint(now, convert.Int64(stats.ZeroOps.Sk))

	// DownOps
	s.mb.RecordNetfsDownloadRequestsDataPoint(now, convert.Int64(stats.DownOps.DL))
	s.mb.RecordNetfsDownloadDoneDataPoint(now, convert.Int64(stats.DownOps.Ds))
	s.mb.RecordNetfsDownloadFailedDataPoint(now, convert.Int64(stats.DownOps.Df))
	s.mb.RecordNetfsDownloadInsteadDataPoint(now, convert.Int64(stats.DownOps.Di))

	// CaRdOps
	s.mb.RecordNetfsCacheReadRequestsDataPoint(now, convert.Int64(stats.CaRdOps.RD))
	s.mb.RecordNetfsCacheReadDoneDataPoint(now, convert.Int64(stats.CaRdOps.Rs))
	s.mb.RecordNetfsCacheReadFailedDataPoint(now, convert.Int64(stats.CaRdOps.Rf))

	// UpldOps
	s.mb.RecordNetfsUploadRequestsDataPoint(now, convert.Int64(stats.UpldOps.UL))
	s.mb.RecordNetfsUploadDoneDataPoint(now, convert.Int64(stats.UpldOps.Us))
	s.mb.RecordNetfsUploadFailedDataPoint(now, convert.Int64(stats.UpldOps.Uf))

	// CaWrOps
	s.mb.RecordNetfsCacheWriteRequestsDataPoint(now, convert.Int64(stats.CaWrOps.WR))
	s.mb.RecordNetfsCacheWriteDoneDataPoint(now, convert.Int64(stats.CaWrOps.Ws))
	s.mb.RecordNetfsCacheWriteFailedDataPoint(now, convert.Int64(stats.CaWrOps.Wf))

	// Retries
	s.mb.RecordNetfsRetriesReadReqDataPoint(now, convert.Int64(stats.Retries.Rq))
	s.mb.RecordNetfsRetriesReadSubreqDataPoint(now, convert.Int64(stats.Retries.Rs))
	s.mb.RecordNetfsRetriesWriteReqDataPoint(now, convert.Int64(stats.Retries.Wq))
	s.mb.RecordNetfsRetriesWriteSubreqDataPoint(now, convert.Int64(stats.Retries.Ws))

	// Objs
	s.mb.RecordNetfsObjectsReadReqsDataPoint(now, convert.Int64(stats.Objs.Rr))
	s.mb.RecordNetfsObjectsSubreqsDataPoint(now, convert.Int64(stats.Objs.Sr))
	s.mb.RecordNetfsObjectsFolioQueueDataPoint(now, convert.Int64(stats.Objs.Foq))
	s.mb.RecordNetfsObjectsWriteConflictsDataPoint(now, convert.Int64(stats.Objs.Wsc))

	// WbLock
	s.mb.RecordNetfsWblockSkipDataPoint(now, convert.Int64(stats.WbLock.Skip))
	s.mb.RecordNetfsWblockWaitDataPoint(now, convert.Int64(stats.WbLock.Wait))
}

func (s *fscacheScraper) recordFscacheMetrics(now pcommon.Timestamp, stats *fscacheStats) {
	// Cookies
	s.mb.RecordFscacheCookiesDataDataPoint(now, convert.Int64(stats.Cookies.N))
	s.mb.RecordFscacheCookiesVolumeDataPoint(now, convert.Int64(stats.Cookies.V))
	s.mb.RecordFscacheCookiesVolumeCollisionsDataPoint(now, convert.Int64(stats.Cookies.Vcol))
	s.mb.RecordFscacheCookiesVolumeOomDataPoint(now, convert.Int64(stats.Cookies.Voom))

	// Acquire
	s.mb.RecordFscacheAcquireRequestsDataPoint(now, convert.Int64(stats.Acquire.N))
	s.mb.RecordFscacheAcquireOkDataPoint(now, convert.Int64(stats.Acquire.Ok))
	s.mb.RecordFscacheAcquireOomDataPoint(now, convert.Int64(stats.Acquire.Oom))

	// LRU
	s.mb.RecordFscacheLruCountDataPoint(now, convert.Int64(stats.LRU.N))
	s.mb.RecordFscacheLruExpiredDataPoint(now, convert.Int64(stats.LRU.Exp))
	s.mb.RecordFscacheLruRemovedDataPoint(now, convert.Int64(stats.LRU.Rmv))
	s.mb.RecordFscacheLruDroppedDataPoint(now, convert.Int64(stats.LRU.Drp))

	// Invals
	s.mb.RecordFscacheInvalidationsDataPoint(now, convert.Int64(stats.Invals.N))

	// Updates
	s.mb.RecordFscacheUpdatesRequestsDataPoint(now, convert.Int64(stats.Updates.N))
	s.mb.RecordFscacheUpdatesResizeDataPoint(now, convert.Int64(stats.Updates.Rsz))
	s.mb.RecordFscacheUpdatesResizeSkippedDataPoint(now, convert.Int64(stats.Updates.Rsn))

	// Relinqs
	s.mb.RecordFscacheRelinquishRequestsDataPoint(now, convert.Int64(stats.Relinqs.N))
	s.mb.RecordFscacheRelinquishRetireDataPoint(now, convert.Int64(stats.Relinqs.Rtr))
	s.mb.RecordFscacheRelinquishDropDataPoint(now, convert.Int64(stats.Relinqs.Drop))

	// NoSpace
	s.mb.RecordFscacheNospaceWriteDataPoint(now, convert.Int64(stats.NoSpace.Nwr))
	s.mb.RecordFscacheNospaceCreateDataPoint(now, convert.Int64(stats.NoSpace.Ncr))
	s.mb.RecordFscacheNospaceCullDataPoint(now, convert.Int64(stats.NoSpace.Cull))

	// IO
	s.mb.RecordFscacheIoReadDataPoint(now, convert.Int64(stats.IO.Rd))
	s.mb.RecordFscacheIoWriteDataPoint(now, convert.Int64(stats.IO.Wr))
	s.mb.RecordFscacheIoMisfitDataPoint(now, convert.Int64(stats.IO.Mis))
}

// parseFscacheStats reads and parses /proc/fs/fscache/stats
func parseFscacheStats(path string) (*fscacheStats, error) {
	file, err := os.Open(path) // #nosec G304 -- path is from trusted configuration, not user input
	if err != nil {
		return nil, fmt.Errorf("failed to open fscache stats file: %w", err)
	}
	defer file.Close()

	stats := &fscacheStats{}
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and separator
		if line == "" || line == "-- FS-Cache statistics --" {
			continue
		}

		// Parse line format: "Category: key=value key=value..."
		if err := parseLine(line, stats); err != nil {
			// Log but continue parsing other lines
			continue
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading fscache stats: %w", err)
	}

	return stats, nil
}

// parseLine parses a single line from the stats file
func parseLine(line string, stats *fscacheStats) error {
	parts := strings.SplitN(line, ":", 2)
	if len(parts) != 2 {
		return fmt.Errorf("invalid line format: %s", line)
	}

	category := strings.TrimSpace(parts[0])
	values := parseKeyValues(parts[1])

	switch category {
	case "Reads":
		stats.Reads.DR = values["DR"]
		stats.Reads.RA = values["RA"]
		stats.Reads.RF = values["RF"]
		stats.Reads.RS = values["RS"]
		stats.Reads.WB = values["WB"]
		stats.Reads.WBZ = values["WBZ"]
	case "Writes":
		stats.Writes.BW = values["BW"]
		stats.Writes.WT = values["WT"]
		stats.Writes.DW = values["DW"]
		stats.Writes.WP = values["WP"]
		stats.Writes.C2 = values["2C"]
	case "ZeroOps":
		stats.ZeroOps.ZR = values["ZR"]
		stats.ZeroOps.Sh = values["sh"]
		stats.ZeroOps.Sk = values["sk"]
	case "DownOps":
		stats.DownOps.DL = values["DL"]
		stats.DownOps.Ds = values["ds"]
		stats.DownOps.Df = values["df"]
		stats.DownOps.Di = values["di"]
	case "CaRdOps":
		stats.CaRdOps.RD = values["RD"]
		stats.CaRdOps.Rs = values["rs"]
		stats.CaRdOps.Rf = values["rf"]
	case "UpldOps":
		stats.UpldOps.UL = values["UL"]
		stats.UpldOps.Us = values["us"]
		stats.UpldOps.Uf = values["uf"]
	case "CaWrOps":
		stats.CaWrOps.WR = values["WR"]
		stats.CaWrOps.Ws = values["ws"]
		stats.CaWrOps.Wf = values["wf"]
	case "Retries":
		stats.Retries.Rq = values["rq"]
		stats.Retries.Rs = values["rs"]
		stats.Retries.Wq = values["wq"]
		stats.Retries.Ws = values["ws"]
	case "Objs":
		stats.Objs.Rr = values["rr"]
		stats.Objs.Sr = values["sr"]
		stats.Objs.Foq = values["foq"]
		stats.Objs.Wsc = values["wsc"]
	case "WbLock":
		stats.WbLock.Skip = values["skip"]
		stats.WbLock.Wait = values["wait"]
	case "Cookies":
		stats.Cookies.N = values["n"]
		stats.Cookies.V = values["v"]
		stats.Cookies.Vcol = values["vcol"]
		stats.Cookies.Voom = values["voom"]
	case "Acquire":
		stats.Acquire.N = values["n"]
		stats.Acquire.Ok = values["ok"]
		stats.Acquire.Oom = values["oom"]
	case "LRU":
		stats.LRU.N = values["n"]
		stats.LRU.Exp = values["exp"]
		stats.LRU.Rmv = values["rmv"]
		stats.LRU.Drp = values["drp"]
		// Intentionally skip "at" - not useful for monitoring
	case "Invals":
		stats.Invals.N = values["n"]
	case "Updates":
		stats.Updates.N = values["n"]
		stats.Updates.Rsz = values["rsz"]
		stats.Updates.Rsn = values["rsn"]
	case "Relinqs":
		stats.Relinqs.N = values["n"]
		stats.Relinqs.Rtr = values["rtr"]
		stats.Relinqs.Drop = values["drop"]
	case "NoSpace":
		stats.NoSpace.Nwr = values["nwr"]
		stats.NoSpace.Ncr = values["ncr"]
		stats.NoSpace.Cull = values["cull"]
	case "IO":
		stats.IO.Rd = values["rd"]
		stats.IO.Wr = values["wr"]
		stats.IO.Mis = values["mis"]
	}

	return nil
}

// parseKeyValues parses "key=value key=value..." into a map
func parseKeyValues(s string) map[string]uint64 {
	result := make(map[string]uint64)

	for pair := range strings.FieldsSeq(s) {
		kv := strings.SplitN(pair, "=", 2)
		if len(kv) != 2 {
			continue
		}
		key := kv[0]
		value, err := strconv.ParseUint(kv[1], 10, 64)
		if err != nil {
			continue
		}
		result[key] = value
	}

	return result
}
