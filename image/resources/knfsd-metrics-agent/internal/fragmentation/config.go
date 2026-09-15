/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fragmentation

//go:generate go run go.opentelemetry.io/collector/cmd/mdatagen metadata.yaml

import (
	"errors"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/fragmentation/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/scraper/scraperhelper"
)

type Config struct {
	scraperhelper.ControllerConfig `mapstructure:",squash"` // ControllerConfig to configure scraping interval (default: 10m)
	metadata.MetricsBuilderConfig  `mapstructure:"metrics"` // MetricsBuilderConfig to enable/disable specific metrics (default: all enabled)
	CachePath                      string                   `mapstructure:"cache_path"`
	MinFileSize                    int64                    `mapstructure:"min_file_size"`
}

func createDefaultConfig() component.Config {
	cfg := scraperhelper.NewDefaultControllerConfig()

	// Collecting extent statistics requires walking the cache and issuing a
	// FIEMAP ioctl per file, so this is significantly more expensive than
	// reading a file under /proc. Scrape less frequently than the other
	// receivers, and use the scrape_duration metric to tune this further.
	cfg.CollectionInterval = 10 * time.Minute

	// Bound the scrape so a very large cache cannot overrun the collection
	// interval. The scraper checks the context while walking, so it aborts
	// cleanly and reports nothing for that cycle.
	cfg.Timeout = 2 * time.Minute

	return &Config{
		ControllerConfig:     cfg,
		MetricsBuilderConfig: metadata.NewDefaultMetricsBuilderConfig(),
		CachePath:            "/var/cache/fscache/cache",

		// Small backing files cannot accumulate enough extents to matter, and
		// they dominate the file count in most caches. Skipping them keeps the
		// scrape cheap without affecting the statistics that are of interest.
		MinFileSize: 1024 * 1024,
	}
}

func (c Config) Validate() error {
	if c.CachePath == "" {
		return errors.New("cache_path cannot be empty")
	}
	if c.MinFileSize < 0 {
		return errors.New("min_file_size cannot be negative")
	}
	return nil
}
