/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package oldestfile

//go:generate go run go.opentelemetry.io/collector/cmd/mdatagen metadata.yaml

import (
	"errors"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/oldestfile/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/scraper/scraperhelper"
)

type Config struct {
	scraperhelper.ControllerConfig `mapstructure:",squash"` // ControllerConfig to configure scraping interval (default: 10m)
	metadata.MetricsBuilderConfig  `mapstructure:"metrics"` // MetricsBuilderConfig to enable/disable specific metrics (default: all enabled)
	CachePath                      string                   `mapstructure:"cache_path"`
}

func createDefaultConfig() component.Config {
	return &Config{
		ControllerConfig: scraperhelper.ControllerConfig{
			CollectionInterval: 10 * time.Minute,
		},
		MetricsBuilderConfig: metadata.NewDefaultMetricsBuilderConfig(),
		CachePath:            "/var/cache/fscache/cache",
	}
}

func (c Config) Validate() error {
	if c.CachePath == "" {
		return errors.New("cache_path cannot be empty")
	}
	return nil
}
