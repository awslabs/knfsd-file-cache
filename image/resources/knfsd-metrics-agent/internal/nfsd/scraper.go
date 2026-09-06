/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package nfsd

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/convert"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/nfsd/internal/metadata"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
)

// poolStats represents a single line from /proc/fs/nfsd/pool_stats
type poolStats struct {
	Pool            int
	PacketsArrived  uint64
	SocketsEnqueued uint64
	ThreadsWoken    uint64
	ThreadsTimedout uint64
}

type nfsdScraper struct {
	mb            *metadata.MetricsBuilder
	logger        *zap.Logger
	poolStatsPath string
}

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger, poolStatsPath string) (scraper.Metrics, error) {
	s := &nfsdScraper{
		mb:            mb,
		logger:        logger,
		poolStatsPath: poolStatsPath,
	}
	return scraper.NewMetrics(s.scrape)
}

func (s *nfsdScraper) scrape(ctx context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping NFSD metrics")

	now := pcommon.NewTimestampFromTime(time.Now())

	// Get thread count via "pgrep -c -x nfsd"
	if err := s.scrapeThreadCount(ctx, now); err != nil {
		s.logger.Warn("Failed to scrape thread count", zap.Error(err))
	}

	// Parse pool_stats for detailed thread pool metrics
	if err := s.scrapePoolStats(now); err != nil {
		s.logger.Warn("Failed to scrape pool_stats", zap.Error(err))
	}

	metrics := s.mb.Emit()

	s.logger.Debug("Emitting metrics",
		zap.Int("MetricCount", metrics.MetricCount()),
		zap.Int("DataPointCount", metrics.DataPointCount()))

	return metrics, nil
}

// scrapeThreadCount reads the NFS server thread count via "pgrep -c -x nfsd"
func (s *nfsdScraper) scrapeThreadCount(ctx context.Context, now pcommon.Timestamp) error {
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "pgrep", "-c", "-x", "nfsd")
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()

	if err != nil {
		if exit, ok := errors.AsType[*exec.ExitError](err); ok {
			return fmt.Errorf("pgrep terminated with exit code %d\n%s", exit.ExitCode(), stderr.String())
		}
		return fmt.Errorf("failed to run pgrep: %w", err)
	}

	count, err := parsePgrepCount(stdout.String())
	if err != nil {
		return fmt.Errorf("failed to parse pgrep output %q: %w", stdout.String(), err)
	}

	s.mb.RecordNfsThreadsDataPoint(now, count)
	s.logger.Debug("NFSD threads", zap.Int64("threads", count))
	return nil
}

// parsePgrepCount parses the stdout of "pgrep -c nfsd" (a single integer) into int64
func parsePgrepCount(stdout string) (int64, error) {
	s := strings.TrimSpace(stdout)
	if s == "" {
		return 0, fmt.Errorf("empty output")
	}
	count, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, err
	}
	if count < 0 {
		return 0, fmt.Errorf("nfsd thread count cannot be negative: %d", count)
	}
	return count, nil
}

// scrapePoolStats parses /proc/fs/nfsd/pool_stats for thread pool metrics
func (s *nfsdScraper) scrapePoolStats(now pcommon.Timestamp) error {
	pools, err := parsePoolStats(s.poolStatsPath)
	if err != nil {
		return fmt.Errorf("failed to parse pool_stats: %w", err)
	}

	// Aggregate stats from all pools
	var totalPacketsArrived uint64
	var totalSocketsEnqueued uint64
	var totalThreadsWoken uint64
	var totalThreadsTimedout uint64

	for _, pool := range pools {
		totalPacketsArrived += pool.PacketsArrived
		totalSocketsEnqueued += pool.SocketsEnqueued
		totalThreadsWoken += pool.ThreadsWoken
		totalThreadsTimedout += pool.ThreadsTimedout
	}

	// Calculate packets deferred: arrived - (enqueued + woken)
	var packetsDeferred int64
	if totalPacketsArrived >= (totalSocketsEnqueued + totalThreadsWoken) {
		packetsDeferred = convert.Int64(totalPacketsArrived - (totalSocketsEnqueued + totalThreadsWoken))
	}

	// Record metrics
	s.mb.RecordNfsPacketsArrivedDataPoint(now, convert.Int64(totalPacketsArrived))
	s.mb.RecordNfsPacketsDeferredDataPoint(now, packetsDeferred)
	s.mb.RecordNfsSocketsEnqueuedDataPoint(now, convert.Int64(totalSocketsEnqueued))
	s.mb.RecordNfsThreadsWokenDataPoint(now, convert.Int64(totalThreadsWoken))
	s.mb.RecordNfsThreadsTimedoutDataPoint(now, convert.Int64(totalThreadsTimedout))

	s.logger.Debug("Parsed pool_stats",
		zap.Uint64("packets_arrived", totalPacketsArrived),
		zap.Int64("packets_deferred", packetsDeferred),
		zap.Uint64("sockets_enqueued", totalSocketsEnqueued),
		zap.Uint64("threads_woken", totalThreadsWoken),
		zap.Uint64("threads_timedout", totalThreadsTimedout))

	return nil
}

// parsePoolStats reads and parses /proc/fs/nfsd/pool_stats
// # pool packets-arrived sockets-enqueued threads-woken threads-timedout
// 0 0 2 0 0
func parsePoolStats(path string) ([]poolStats, error) {
	file, err := os.Open(path) // #nosec G304 -- path is from trusted configuration, not user input
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var pools []poolStats
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := scanner.Text()

		// Skip comment lines (starting with #)
		if strings.HasPrefix(line, "#") {
			continue
		}

		// Skip empty lines
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		pool, err := strconv.Atoi(fields[0])
		if err != nil {
			continue
		}

		packetsArrived, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			continue
		}

		socketsEnqueued, err := strconv.ParseUint(fields[2], 10, 64)
		if err != nil {
			continue
		}

		threadsWoken, err := strconv.ParseUint(fields[3], 10, 64)
		if err != nil {
			continue
		}

		threadsTimedout, err := strconv.ParseUint(fields[4], 10, 64)
		if err != nil {
			continue
		}

		pools = append(pools, poolStats{
			Pool:            pool,
			PacketsArrived:  packetsArrived,
			SocketsEnqueued: socketsEnqueued,
			ThreadsWoken:    threadsWoken,
			ThreadsTimedout: threadsTimedout,
		})
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return pools, nil
}
