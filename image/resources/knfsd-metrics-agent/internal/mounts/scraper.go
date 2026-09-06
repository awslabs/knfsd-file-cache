/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package mounts

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/convert"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/mounts/internal/metadata"
	"github.com/prometheus/procfs"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
)

type mountsScraper struct {
	cfg      *Config
	excludes queryProxyInstanceExcludes
	logger   *zap.Logger // Logger to log events
	p        procfs.Proc
	mb       *metadata.MetricsBuilder // MetricsBuilder to build metrics
	nic      *nodeInfoClient
	previous map[string]nfsStats
}

type queryProxyInstanceExcludes struct {
	servers    stringSet
	localPaths pathSet
}

type nfsStats struct {
	server string
	// included if QueryInstanceName is true
	instance string
	summary  summary
}

type nodeInfoClient http.Client

type op struct {
	rttPerOp float64
	exePerOp float64
}

type nodeInfo struct {
	Name string `json:"name"`
}

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger, cfg *Config) (scraper.Metrics, error) {
	s := &mountsScraper{
		cfg: cfg,
		excludes: queryProxyInstanceExcludes{
			servers:    newStringSet(cfg.QueryProxyInstance.Exclude.Servers),
			localPaths: newPathSet(cfg.QueryProxyInstance.Exclude.LocalPaths),
		},
		mb:     mb,
		nic:    createNodeInfoClient(cfg),
		logger: logger,
	}
	return scraper.NewMetrics(
		s.scrape,
		scraper.WithStart(s.start),
	)
}

func createNodeInfoClient(cfg *Config) *nodeInfoClient {
	if !cfg.QueryProxyInstance.Enabled {
		return nil
	}
	return &nodeInfoClient{
		Timeout: cfg.QueryProxyInstance.Timeout,
	}
}

func (s *mountsScraper) start(context.Context, component.Host) error {
	fs, err := procfs.NewDefaultFS()
	if err != nil {
		return err
	}

	p, err := fs.Self()
	if err != nil {
		return err
	}

	s.p = p
	return nil
}

func (s *mountsScraper) scrape(context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping mounts")

	agg, err := s.aggregateNFSStats()
	if err != nil {
		return pmetric.NewMetrics(), err
	}
	s.queryInstanceNames(agg)

	stats := agg.Totals()
	now := pcommon.NewTimestampFromTime(time.Now())
	for _, stat := range stats {
		s.report(stat, now)
	}
	s.track(stats)

	return s.mb.Emit(), nil
}

// aggregateNFSStats reads /proc/self/mountstats and aggregates the stats to
// return a single total per source server.
func (s *mountsScraper) aggregateNFSStats() (nfsStatsAggregator, error) {
	ids, err := s.findNFSDeviceIDs()
	if err != nil {
		return nil, err
	}

	mounts, err := s.p.MountStats()
	if err != nil {
		return nil, err
	}

	agg := make(nfsStatsAggregator)
	for _, m := range mounts {
		if !isNFS(m.Type) {
			continue
		}

		blkid := ids[m.Mount]
		if blkid == "" {
			// This can happen if the mounts change between scraping mountinfo
			// and scraping mountstats. For example auto-mounting a nested
			// mount.
			//
			// Ignore the mount for this scrape, the block device ID should be
			// present on the next scrape. Without the block device ID it's not
			// possible to de-duplicate the io_stats.
			s.logger.Debug("skipping mount, block device ID not found", zap.String("mount", m.Mount))
			continue
		}

		agg.AddMount(blkid, m)
	}
	return agg, nil
}

// findNFSDeviceIDs reads /proc/self/mountinfo to create a mapping of NFS mount
// points to their virtual block device IDs.
func (s *mountsScraper) findNFSDeviceIDs() (map[string]string, error) {
	ids := make(map[string]string)
	mounts, err := s.p.MountInfo()
	if err != nil {
		return ids, err
	}

	for _, m := range mounts {
		if !isNFS(m.FSType) {
			continue
		}
		ids[m.MountPoint] = m.MajorMinorVer
	}
	return ids, nil
}

type nfsStatsAggregator map[string]nfsStatsGroup

type nfsStatsGroup struct {
	nfsStats

	// track local paths included in this server group
	localPaths stringSet

	// track virtual block IDs that are already included in the stats
	blockIDs stringSet
}

func (agg nfsStatsAggregator) AddMount(blkid string, mount *procfs.Mount) {
	stats, ok := mount.Stats.(*procfs.MountStatsNFS)
	if !ok {
		return
	}

	server, _ := splitNFSDevice(mount.Device)

	grp, found := agg[server]
	if !found {
		grp = nfsStatsGroup{
			server:     server,
			localPaths: make(stringSet),
			blockIDs:   make(stringSet),
		}
		agg[server] = grp
	}

	// Always track the local path in case the same remote export has multiple
	// local mounts.
	grp.localPaths.Add(mount.Mount)

	// Check if this mount shares the same io_stats as a previous mount
	//
	// Although the NFS stats are reported per mount multiple mounts can share
	// the same io_stats record in the kernel.
	//
	// When multiple mounts share the same io_stats record, the same stats will
	// be reported multiple times, once for each mount sharing the io_stats
	// record.
	//
	// If these duplicated stats are added together then the stats will
	// effectively be multiplied by the number of mounts sharing the same
	// io_stats record.
	//
	// In the kernel source, io_stats is a member of nfs_server, and nfs_server
	// has a 1:1 correlation with super_block. Each NFS super_block is allocated
	// a virtual block device ID using the get_anon_bdev function.
	//
	// NOTE: Multiple, nfs_server records can share the same RPC client, so its
	// possible (and common) for multiple mounts to have separate io_stats but
	// share the same RPC clients. The RPC clients are denoted by the xprt lines
	// in mountstats (procfs.NFSTransportStats).
	if grp.blockIDs.Contains(blkid) {
		return
	}

	grp.blockIDs.Add(blkid)
	grp.summary = addSummary(newSummary(stats), grp.summary)
	agg[server] = grp
}

func (agg nfsStatsAggregator) Totals() []nfsStats {
	totals := make([]nfsStats, 0, len(agg))
	for _, grp := range agg {
		totals = append(totals, grp.nfsStats)
	}
	return totals
}

func (s *mountsScraper) queryInstanceNames(agg nfsStatsAggregator) {
	if !s.cfg.QueryProxyInstance.Enabled {
		s.logger.Debug("not resolving instance names, QueryProxyInstance is disabled")
		return
	}

	s.logger.Debug("querying instance names")

	// TODO: Consider optimising this by running queries in parallel.
	// TODO: Exponential backoff (per server) if a query keeps failing.
	for key, grp := range agg {
		server := grp.server

		if s.excludes.servers.Contains(server) {
			s.logger.Debug("skipped server, excluded by server", zap.String("server", server))
			continue
		}

		if s.excludes.localPaths.ContainsAny(grp.localPaths) {
			s.logger.Debug("skipped server, excluded by local path", zap.String("server", server))
			continue
		}

		instance, err := s.nic.queryInstanceName(server)

		switch {
		case err != nil:
			s.logger.Warn("failed to query instance name", zap.String("server", server))
			// In case the lookup failed due to a transient error assume the
			// instance name has not changed since the last scrape.
			grp.instance = s.previousInstanceName(server)
		case instance == "":
			s.logger.Warn("instance name resolved as empty string", zap.String("server", server))
			// Assume this is also due to some kind of transient error.
			grp.instance = s.previousInstanceName(server)
		default:
			s.logger.Debug("resolved proxy instance", zap.String("server", server), zap.String("instance", instance))
			grp.instance = instance
		}

		agg[key] = grp
	}
}

func (s *mountsScraper) previousInstanceName(server string) string {
	return s.previous[server].instance
}

func (c *nodeInfoClient) queryInstanceName(addr string) (string, error) {
	// this shouldn't happen, but just in case do not cause a panic
	if c == nil {
		return "", nil
	}

	var err error
	url := fmt.Sprintf("http://%s/api/v1/nodeInfo", addr)
	resp, err := (*http.Client)(c).Get(url)

	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var info nodeInfo
	decoder := json.NewDecoder(resp.Body)
	err = decoder.Decode(&info)
	if err != nil {
		return "", err
	}

	return info.Name, nil
}

func (s *mountsScraper) report(mount nfsStats, now pcommon.Timestamp) {
	s.mb.RecordNfsMountReadBytesDataPoint(now, convert.Int64(mount.summary.bytes.ReadTotal), mount.server, mount.instance)
	s.mb.RecordNfsMountWriteBytesDataPoint(now, convert.Int64(mount.summary.bytes.WriteTotal), mount.server, mount.instance)

	for _, op := range mount.summary.operations {
		s.mb.RecordNfsMountOperationRequestsDataPoint(now, convert.Int64(op.Requests), mount.server, mount.instance, op.Operation)
		s.mb.RecordNfsMountOperationSentBytesDataPoint(now, convert.Int64(op.BytesSent), mount.server, mount.instance, op.Operation)
		s.mb.RecordNfsMountOperationReceivedBytesDataPoint(now, convert.Int64(op.BytesReceived), mount.server, mount.instance, op.Operation)
		s.mb.RecordNfsMountOperationMajorTimeoutsDataPoint(now, convert.Int64(op.MajorTimeouts), mount.server, mount.instance, op.Operation)
		s.mb.RecordNfsMountOperationErrorsDataPoint(now, convert.Int64(op.Errors), mount.server, mount.instance, op.Operation)
	}

	// report original delta based metrics
	s.reportDelta(mount, now)
}

func (s *mountsScraper) reportDelta(stats nfsStats, now pcommon.Timestamp) {
	// TODO: Report counters instead of gauges

	// This is a direct port of the original script that used
	// nfsiostat, so is limited to the data that was output by nfsiostat.
	// Now that we have the raw data we can report a lot more metrics.
	// We can also use counters instead of calculating the diff for many of
	// the metrics and let the monitoring tool calculate the rate.

	// This is a new mount, no previous metrics yet so cannot calculate a diff
	// on this scrape.
	prev, found := s.previous[stats.server]
	if !found {
		return
	}

	// if new.age < prev.summary.age, then the counters must have reset
	// i.e. the NFS share was re-mounted.
	// If the counters have reset then we cannot derive any useful metrics
	// on this scrape, so just treat this as if it were a new summary.
	if stats.summary.age <= prev.summary.age {
		return
	}

	diff := diffSummary(stats.summary, prev.summary)

	delta := diff.age.Seconds()
	if delta <= 0 {
		// This should not happen, as any summaries that have an age smaller
		// than the previous entry are handled as a reset to the counters.
		// Just in case, skip reporting this scrape to avoid divide by zero
		// errors or spurious values.
		return
	}

	sends := float64(diff.transport.Sends)
	var backlog float64
	if sends > 0 {
		backlog = float64(diff.transport.CumulativeBacklog) / sends
	}
	read := calc(diff.operations["READ"])
	write := calc(diff.operations["WRITE"])

	s.mb.RecordNfsMountOpsPerSecondDataPoint(now, sends/delta, stats.server, stats.instance)
	s.mb.RecordNfsMountRPCBacklogDataPoint(now, backlog/delta, stats.server, stats.instance)
	s.mb.RecordNfsMountReadExeDataPoint(now, read.exePerOp, stats.server, stats.instance)
	s.mb.RecordNfsMountReadRttDataPoint(now, read.rttPerOp, stats.server, stats.instance)
	s.mb.RecordNfsMountWriteExeDataPoint(now, write.exePerOp, stats.server, stats.instance)
	s.mb.RecordNfsMountWriteRttDataPoint(now, write.rttPerOp, stats.server, stats.instance)
}

func calc(diff procfs.NFSOperationStats) op {
	ops := float64(diff.Requests)
	// retrans := float64(diff.Transmissions) - float64(diff.Requests)
	// kilobytes := float64(diff.BytesSent+diff.BytesReceived) / 1024
	// queuedFor := float64(diff.CumulativeQueueMilliseconds)
	rtt := float64(diff.CumulativeTotalRequestMilliseconds)
	exe := float64(diff.CumulativeTotalResponseMilliseconds)
	// errs := float64(diff.Errors)

	// var kbPerOp, retransPercent, queuedForPerOp, errsPercent float64
	var rttPerOp, exePerOp float64
	if diff.Requests > 0 {
		// kbPerOp = kilobytes / ops
		// retransPercent = (retrans * 100) / ops
		rttPerOp = rtt / ops
		exePerOp = exe / ops
		// queuedForPerOp = queuedFor / ops
		// errsPercent = (errs * 100) / ops
	}

	return op{rttPerOp, exePerOp}
}

func (s *mountsScraper) track(stats []nfsStats) {
	previous := make(map[string]nfsStats, len(stats))
	for _, m := range stats {
		previous[m.server] = m
	}
	s.previous = previous
}

func isNFS(s string) bool {
	return s == "nfs" || s == "nfs4"
}

func splitNFSDevice(s string) (server string, path string) {
	parts := strings.SplitN(s, ":", 2)
	switch len(parts) {
	case 0:
		return "", ""
	case 1:
		// shouldn't happen, do our best to return something sensible
		return "", parts[0]
	default:
		return parts[0], parts[1]
	}
}

type pathSet map[string]struct{}
type stringSet map[string]struct{}

func newPathSet(paths []string) pathSet {
	ps := make(pathSet, len(paths))
	for _, p := range paths {
		p = path.Clean(p)
		ps[p] = struct{}{}
	}
	return ps
}

func (ps pathSet) ContainsAny(s stringSet) bool {
	if len(ps) == 0 {
		return false
	}
	for p := range s {
		if ps.Contains(p) {
			return true
		}
	}
	return false
}

func (ps pathSet) Contains(p string) bool {
	if len(ps) == 0 {
		return false
	}
	p = path.Clean(p)
	_, found := ps[p]
	return found
}

func newStringSet(items []string) stringSet {
	set := make(stringSet, len(items))
	for _, s := range items {
		set[s] = struct{}{}
	}
	return set
}

func (set stringSet) Add(s string) {
	set[s] = struct{}{}
}

func (set stringSet) Contains(s string) bool {
	_, found := set[s]
	return found
}
