/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package nfsd

//go:generate go run go.opentelemetry.io/collector/cmd/mdatagen metadata.yaml

import (
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/nfsd/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/scraper/scraperhelper"
)

type Config struct {
	scraperhelper.ControllerConfig `mapstructure:",squash"`
	metadata.MetricsBuilderConfig  `mapstructure:"metrics"`
	PoolStatsPath                  string `mapstructure:"pool_stats_path"`
}

func createDefaultConfig() component.Config {
	return &Config{
		ControllerConfig:     scraperhelper.NewDefaultControllerConfig(),
		MetricsBuilderConfig: metadata.NewDefaultMetricsBuilderConfig(),
		PoolStatsPath:        "/proc/fs/nfsd/pool_stats",
	}
}
