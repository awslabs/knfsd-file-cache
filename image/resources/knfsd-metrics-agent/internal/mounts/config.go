/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package mounts

//go:generate go run go.opentelemetry.io/collector/cmd/mdatagen metadata.yaml

import (
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/mounts/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/scraper/scraperhelper"
)

type Config struct {
	scraperhelper.ControllerConfig `mapstructure:",squash"` // ControllerConfig to configure scraping interval (default: 1m)
	metadata.MetricsBuilderConfig  `mapstructure:"metrics"` // MetricsBuilderConfig to enable/disable specific metrics (default: all enabled)

	// Query the knfsd-agent service to find out which instance a client is
	// connected to, and include an instance attribute in the metrics.
	// This is used to enrich the client metrics with the name of the instance
	// the client is connected to, as the source attribute will only indicate
	// the IP of the load balancer.
	// The load balancer is assumed to have session affinity based upon client
	// IP only, so that all the connections from a client to the same IP will
	// use the same instance.
	QueryProxyInstance QueryProxyInstanceConfig `mapstructure:"query_proxy_instance"`
}

type QueryProxyInstanceConfig struct {
	Enabled bool                             `mapstructure:"enabled"`
	Timeout time.Duration                    `mapstructure:"timeout"`
	Exclude QueryProxyInstanceExcludesConfig `mapstructure:"exclude"`
}

type QueryProxyInstanceExcludesConfig struct {
	Servers    []string `mapstructure:"servers"`
	LocalPaths []string `mapstructure:"local_paths"`
}

func createDefaultConfig() component.Config {
	return &Config{
		ControllerConfig:     scraperhelper.NewDefaultControllerConfig(),
		MetricsBuilderConfig: metadata.DefaultMetricsBuilderConfig(),
		QueryProxyInstance: QueryProxyInstanceConfig{
			Enabled: false,
			Timeout: 10 * time.Second,
		},
	}
}
