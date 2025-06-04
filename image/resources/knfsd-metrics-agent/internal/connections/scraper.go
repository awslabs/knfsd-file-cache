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

// newScraper is a constructor function which returns a new scraper instance
func newScraper(mb *metadata.MetricsBuilder, logger *zap.Logger) (scraper.Metrics, error) {
	s := &connectionsScraper{
		mb:     mb,
		logger: logger,
	}
	return scraper.NewMetrics(s.scrape)
}

func (s *connectionsScraper) scrape(ctx context.Context) (pmetric.Metrics, error) {
	s.logger.Debug("Scraping NFS connections")

	// TODO: Consider counting unique clients (by IP) as well as total connections
	count, err := countConnectedClients(ctx)
	if err != nil {
		return pmetric.NewMetrics(), err
	}

	now := pcommon.NewTimestampFromTime(time.Now())

	s.mb.RecordNfsConnectionsDataPoint(now, count)

	s.logger.Debug("NFS connections", zap.Int64("count", count))

	return s.mb.Emit(), nil
}

func countConnectedClients(ctx context.Context) (int64, error) {
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "ss",
		"--no-header", "--oneline", "--numeric",
		"--tcp", "--udp",
		"state", "established",
		"sport", "2049",
	)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()

	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			err = fmt.Errorf("command terminated with exit code %d\n%s", exit.ExitCode(), stderr.String())
		}
		return 0, err
	}

	var count int64
	s := bufio.NewScanner(&stdout)
	for s.Scan() {
		count++
	}

	err = s.Err()
	if err != nil {
		return 0, err
	}

	return count, nil
}
