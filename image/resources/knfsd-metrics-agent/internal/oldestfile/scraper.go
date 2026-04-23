/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package oldestfile

import (
	"context"
	"errors"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/oldestfile/internal/metadata"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
)

type oldestFileScraper struct {
	mb        *metadata.MetricsBuilder // MetricsBuilder to build metrics
	logger    *zap.Logger              // Logger to log events
	cachePath string
	last      oldestFile
}

type oldestFile struct {
	path  string
	mtime time.Time
}

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger, cachePath string) (scraper.Metrics, error) {
	s := &oldestFileScraper{
		mb:        mb,
		logger:    logger,
		cachePath: cachePath,
	}
	return scraper.NewMetrics(s.scrape)
}

func (s *oldestFileScraper) scrape(ctx context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping oldest file")

	age, err := s.findOldest(ctx)
	if err != nil {
		return pmetric.NewMetrics(), nil
	}

	now := pcommon.NewTimestampFromTime(time.Now())

	s.mb.RecordFscacheOldestFileDataPoint(now, int64(age.Seconds()))

	s.logger.Debug("Scraped oldest file", zap.Duration("age", age))

	return s.mb.Emit(), nil
}

func (s *oldestFileScraper) findOldest(ctx context.Context) (time.Duration, error) {
	oldest, err := s.findOldestFile(ctx)
	if err != nil {
		s.last = oldestFile{}
		return 0, err
	}
	s.last = oldest

	if oldest.mtime.IsZero() {
		return 0, nil
	}

	now := time.Now()
	age := max(now.Sub(oldest.mtime), time.Duration(0))

	return age, nil
}

func (s *oldestFileScraper) findOldestFile(ctx context.Context) (oldestFile, error) {
	// optimistic check if the oldest file from a previous scrape still exists
	if s.last.path != "" {
		stat, err := os.Stat(s.last.path)
		if err == nil && stat.ModTime().Equal(s.last.mtime) {
			// assume the file is still the oldest
			return s.last, nil
		}
	}

	count := 0
	found := oldestFile{}

	// exit if the cache_path does not exist
	if _, err := os.Stat(s.cachePath); errors.Is(err, os.ErrNotExist) {
		log.Fatalf("cache_path does not exist")
	}

	err := filepath.WalkDir(s.cachePath, func(path string, d fs.DirEntry, err error) error {
		// Avoiding checking the context on every single file. This is because
		// checking the context has to lock a mutex.
		// No heuristics for a good value here, so just chose 100 arbitrarily.
		count++
		if count > 100 {
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
			// if there's an error querying file, just skip the file
			return nil
		}

		mtime := info.ModTime()
		if mtime.IsZero() {
			return nil
		}

		if found.mtime.IsZero() || mtime.Before(found.mtime) {
			found = oldestFile{
				path:  path,
				mtime: mtime,
			}
		}

		return nil
	})
	return found, err
}
