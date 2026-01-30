/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fscache

//go:generate go run go.opentelemetry.io/collector/cmd/mdatagen metadata.yaml

import (
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/fscache/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/scraper/scraperhelper"
)

type Config struct {
	scraperhelper.ControllerConfig `mapstructure:",squash"`
	metadata.MetricsBuilderConfig  `mapstructure:"metrics"`
	StatsPath                      string `mapstructure:"stats_path"`
}

func createDefaultConfig() component.Config {
	return &Config{
		ControllerConfig:     scraperhelper.NewDefaultControllerConfig(),
		MetricsBuilderConfig: metadata.DefaultMetricsBuilderConfig(),
		StatsPath:            "/proc/fs/fscache/stats",
	}
}
