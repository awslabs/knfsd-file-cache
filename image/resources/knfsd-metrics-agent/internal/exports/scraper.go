/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package exports

import (
	"context"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/convert"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/exports/internal/metadata"
	"github.com/prometheus/procfs/nfs"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
)

type exportsScraper struct {
	mb     *metadata.MetricsBuilder // MetricsBuilder to build metrics
	logger *zap.Logger              // Logger to log events
}

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger) (scraper.Metrics, error) {
	s := &exportsScraper{
		mb:     mb,
		logger: logger,
	}
	return scraper.NewMetrics(s.scrape)
}

func (s *exportsScraper) scrape(context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping NFS metrics")

	fs, err := nfs.NewDefaultFS()
	if err != nil {
		return pmetric.NewMetrics(), err
	}

	now := pcommon.NewTimestampFromTime(time.Now())

	stats, err := fs.ServerRPCStats()
	if err != nil {
		return pmetric.NewMetrics(), err
	}

	ops := totalOperations(stats)

	s.mb.RecordNfsExportsTotalOperationsDataPoint(now, convert.Int64(ops))
	s.mb.RecordNfsExportsTotalReadBytesDataPoint(now, convert.Int64(stats.InputOutput.Read))
	s.mb.RecordNfsExportsTotalWriteBytesDataPoint(now, convert.Int64(stats.InputOutput.Write))

	metrics := s.mb.Emit()

	s.logger.Debug("Emitting metrics", zap.Int("MetricCount", metrics.MetricCount()), zap.Int("DataPointCount", metrics.DataPointCount()))

	return metrics, nil
}

func totalOperations(stats *nfs.ServerRPCStats) uint64 {
	var ops uint64

	// Total up all the operations. Not using stats.ServerRPC.RPCCount because
	// NFSv4 can have multiple operations in a single RPC call as NFSv4 only has
	// two RPC calls, NULL and COMPOUND.
	// ignore V2Stats, NFS v2 is obsolete

	ops += stats.V3Stats.Null
	ops += stats.V3Stats.GetAttr
	ops += stats.V3Stats.SetAttr
	ops += stats.V3Stats.Lookup
	ops += stats.V3Stats.Access
	ops += stats.V3Stats.ReadLink
	ops += stats.V3Stats.Read
	ops += stats.V3Stats.Write
	ops += stats.V3Stats.Create
	ops += stats.V3Stats.MkDir
	ops += stats.V3Stats.SymLink
	ops += stats.V3Stats.MkNod
	ops += stats.V3Stats.Remove
	ops += stats.V3Stats.RmDir
	ops += stats.V3Stats.Rename
	ops += stats.V3Stats.Link
	ops += stats.V3Stats.ReadDir
	ops += stats.V3Stats.ReadDirPlus
	ops += stats.V3Stats.FsStat
	ops += stats.V3Stats.FsInfo
	ops += stats.V3Stats.PathConf
	ops += stats.V3Stats.Commit

	ops += stats.ServerV4Stats.Null
	// ignore ServerV4Stats.Compound as it only groups the operations below
	ops += stats.V4Ops.Access
	ops += stats.V4Ops.Close
	ops += stats.V4Ops.Commit
	ops += stats.V4Ops.Create
	ops += stats.V4Ops.DelegPurge
	ops += stats.V4Ops.DelegReturn
	ops += stats.V4Ops.GetAttr
	ops += stats.V4Ops.GetFH
	ops += stats.V4Ops.Link
	ops += stats.V4Ops.Lock
	ops += stats.V4Ops.Lockt
	ops += stats.V4Ops.Locku
	ops += stats.V4Ops.Lookup
	ops += stats.V4Ops.LookupRoot
	ops += stats.V4Ops.Nverify
	ops += stats.V4Ops.Open
	ops += stats.V4Ops.OpenAttr
	ops += stats.V4Ops.OpenConfirm
	ops += stats.V4Ops.OpenDgrd
	ops += stats.V4Ops.PutFH
	ops += stats.V4Ops.PutPubFH
	ops += stats.V4Ops.PutRootFH
	ops += stats.V4Ops.Read
	ops += stats.V4Ops.ReadDir
	ops += stats.V4Ops.ReadLink
	ops += stats.V4Ops.Remove
	ops += stats.V4Ops.Rename
	ops += stats.V4Ops.Renew
	ops += stats.V4Ops.RestoreFH
	ops += stats.V4Ops.SaveFH
	ops += stats.V4Ops.SecInfo
	ops += stats.V4Ops.SetAttr
	ops += stats.V4Ops.Verify
	ops += stats.V4Ops.Write
	ops += stats.V4Ops.RelLockOwner

	return ops
}
