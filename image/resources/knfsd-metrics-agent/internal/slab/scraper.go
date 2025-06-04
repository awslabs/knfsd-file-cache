/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package slab

import (
	"context"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/slab/internal/metadata"
	"github.com/prometheus/procfs"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
)

type slabScraper struct {
	mb     *metadata.MetricsBuilder // MetricsBuilder to build metrics
	logger *zap.Logger              // Logger to log events
	fs     procfs.FS                // Read slabinfo from /proc filesystem
}

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger) (scraper.Metrics, error) {
	s := &slabScraper{
		mb:     mb,
		logger: logger,
	}
	return scraper.NewMetrics(
		s.scrape,
		scraper.WithStart(s.start))
}

func (s *slabScraper) start(context.Context, component.Host) error {
	fs, err := procfs.NewDefaultFS()
	if err != nil {
		return err
	}

	// Verify we can scrape slabinfo, most common reason this will fail is
	// because of permissions (needs to be root).
	_, err = fs.SlabInfo()
	// TODO: check for transient errors?
	if err != nil {
		return err
	}

	s.fs = fs
	return nil
}

// scrape function that scrapes slabinfo matching the pattern for specific metrics
func (s *slabScraper) scrape(ctx context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping /proc/slabinfo")

	info, err := s.fs.SlabInfo()
	if err != nil {
		return pmetric.NewMetrics(), err
	}

	s.logger.Debug("Found /proc/slabinfo", zap.Any("info", info))

	now := pcommon.NewTimestampFromTime(time.Now())

	dentry := find(info.Slabs, "dentry")
	if dentry != nil {
		s.mb.RecordSlabDentryCacheActiveObjectsDataPoint(now, dentry.ObjActive)
		s.mb.RecordSlabDentryCacheObjsizeDataPoint(now, dentry.ObjSize)
	}

	nfs := find(info.Slabs, "nfs_inode_cache")
	if nfs != nil {
		s.mb.RecordSlabNfsInodeCacheActiveObjectsDataPoint(now, nfs.ObjActive)
		s.mb.RecordSlabNfsInodeCacheObjsizeDataPoint(now, nfs.ObjSize)
	}

	metrics := s.mb.Emit()

	s.logger.Debug("Emitting metrics", zap.Int("MetricCount", metrics.MetricCount()), zap.Int("DataPointCount", metrics.DataPointCount()))

	return metrics, nil
}

func find(slabs []*procfs.Slab, name string) *procfs.Slab {
	for _, s := range slabs {
		if s.Name == name {
			return s
		}
	}
	return nil
}
