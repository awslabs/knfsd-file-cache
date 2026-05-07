/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package slab

//go:generate go run go.opentelemetry.io/collector/cmd/mdatagen metadata.yaml

import (
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/slab/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/scraper/scraperhelper"
)

type Config struct {
	scraperhelper.ControllerConfig `mapstructure:",squash"` // ControllerConfig to configure scraping interval (default: 1m)
	metadata.MetricsBuilderConfig  `mapstructure:"metrics"` // MetricsBuilderConfig to enable/disable specific metrics (default: all enabled)
}

func createDefaultConfig() component.Config {
	return &Config{
		ControllerConfig:     scraperhelper.NewDefaultControllerConfig(),
		MetricsBuilderConfig: metadata.NewDefaultMetricsBuilderConfig(),
	}
}
