/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package connections

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/connections/internal/metadata"
	"go.opentelemetry.io/collector/pdata/pcommon"
	"go.opentelemetry.io/collector/pdata/pmetric"
	"go.opentelemetry.io/collector/scraper"
	"go.uber.org/zap"
)

type connectionsScraper struct {
	mb     *metadata.MetricsBuilder // MetricsBuilder to build metrics
	logger *zap.Logger              // Logger to log events
}

// connectionCounts holds both established and unique client counts
type connectionCounts struct {
	established int64 // Number of ESTABLISHED connections (nfs.connections)
	clients     int64 // Number of unique client IPs in any connected state (nfs.clients)
}

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger) (scraper.Metrics, error) {
	s := &connectionsScraper{
		mb:     mb,
		logger: logger,
	}
	return scraper.NewMetrics(s.scrape)
}

func (s *connectionsScraper) scrape(ctx context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping NFS connections/clients")

	counts, err := countConnectedClients(ctx)
	if err != nil {
		return pmetric.NewMetrics(), err
	}

	now := pcommon.NewTimestampFromTime(time.Now())

	s.mb.RecordNfsConnectionsDataPoint(now, counts.established)
	s.mb.RecordNfsClientsDataPoint(now, counts.clients)

	s.logger.Debug("Emitting metrics",
		zap.Int64("nfs.connections", counts.established),
		zap.Int64("nfs.clients", counts.clients),
	)

	return s.mb.Emit(), nil
}

func countConnectedClients(ctx context.Context) (connectionCounts, error) {
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "ss",
		"--no-header", "--oneline", "--numeric",
		"--tcp", "--udp",
		"state", "connected",
		"sport", "2049",
	)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()

	if err != nil {
		if exit, ok := errors.AsType[*exec.ExitError](err); ok {
			err = fmt.Errorf("command terminated with exit code %d\n%s", exit.ExitCode(), stderr.String())
		}
		return connectionCounts{}, err
	}

	return parseSSOutput(stdout.Bytes())
}

// parseSSOutput parses the output of the ss command and returns connection counts.
// The ss --oneline output format is:
// Netid State Recv-Q Send-Q LocalAddr:Port PeerAddr:Port
// e.g.: tcp   ESTAB 0      0      10.0.1.5:2049 10.0.2.100:45678
//
// Returns:
//   - established: count of connections in ESTAB state only (nfs.connections)
//   - clients: count of unique client IPs in any connected state (nfs.clients)
func parseSSOutput(data []byte) (connectionCounts, error) {
	uniqueClients := make(map[string]struct{})
	var established int64

	s := bufio.NewScanner(bytes.NewReader(data))
	for s.Scan() {
		line := s.Text()
		fields := strings.Fields(line)
		if len(fields) < 6 {
			continue
		}

		// Count ESTAB connections for nfs.connections metric
		state := fields[1]
		if state == "ESTAB" {
			established++
		}

		// Extract unique client IPs from all connected states for nfs.clients metric
		ip := extractPeerIP(line)
		if ip != "" {
			uniqueClients[ip] = struct{}{}
		}
	}

	if err := s.Err(); err != nil {
		return connectionCounts{}, err
	}

	return connectionCounts{
		established: established,
		clients:     int64(len(uniqueClients)),
	}, nil
}

// extractPeerIP extracts the peer IP address from an ss output line.
// Handles both IPv4 (10.0.2.100:45678) and IPv6 ([::1]:45678 or ::1:45678) formats.
func extractPeerIP(line string) string {
	fields := strings.Fields(line)
	if len(fields) < 6 {
		return ""
	}

	// Peer address is the 6th field (index 5)
	peerAddr := fields[5]

	// Handle IPv6 with brackets: [::1]:port
	if strings.HasPrefix(peerAddr, "[") {
		if idx := strings.LastIndex(peerAddr, "]:"); idx != -1 {
			return peerAddr[1:idx]
		}
		return ""
	}

	// Handle IPv4 and IPv6 without brackets
	// For IPv4: 10.0.2.100:45678 -> last colon separates IP and port
	// For IPv6: ::1:45678 -> need to find the last colon that separates port
	if idx := strings.LastIndex(peerAddr, ":"); idx != -1 {
		return peerAddr[:idx]
	}

	return ""
}
