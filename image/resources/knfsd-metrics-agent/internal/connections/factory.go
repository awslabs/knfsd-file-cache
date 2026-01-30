/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package connections

import (
	"context"
	"errors"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/connections/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/consumer"
	"go.opentelemetry.io/collector/receiver"
	"go.opentelemetry.io/collector/scraper/scraperhelper"
	"go.uber.org/zap"
)

var errWrongConfig = errors.New("config was not a connections receiver config")

func NewFactory() receiver.Factory {
	return receiver.NewFactory(
		metadata.Type,
		createDefaultConfig,
		receiver.WithMetrics(createMetricsReceiver, component.StabilityLevelAlpha),
	)
}

func createMetricsReceiver(
	ctx context.Context,
	set receiver.Settings,
	cc component.Config,
	con consumer.Metrics,

) (receiver.Metrics, error) {
	cfg, ok := cc.(*Config)
	if !ok {
		return nil, errWrongConfig
	}

	mb := metadata.NewMetricsBuilder(cfg.MetricsBuilderConfig, set)

	s, err := newScraper(mb, set.Logger)
	if err != nil {
		set.Logger.Error("failed to create new scraper helper", zap.Error(err))
		return nil, err
	}

	return scraperhelper.NewMetricsController(
		&cfg.ControllerConfig,
		set,
		con,
		scraperhelper.AddMetricsScraper(metadata.Type, s),
	)
}
