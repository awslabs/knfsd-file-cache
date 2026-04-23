/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/connections"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/exports"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/fscache"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/mounts"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/nfsd"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/oldestfile"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/internal/slab"

	"go.opentelemetry.io/collector/otelcol"
	"go.opentelemetry.io/collector/service/telemetry/otelconftelemetry"

	"go.opentelemetry.io/collector/exporter/debugexporter"
	"go.opentelemetry.io/collector/exporter/otlpexporter"
	"go.opentelemetry.io/collector/exporter/otlphttpexporter"
	"go.opentelemetry.io/collector/extension/zpagesextension"
	"go.opentelemetry.io/collector/processor/memorylimiterprocessor"
	"go.opentelemetry.io/collector/receiver/otlpreceiver"

	"github.com/open-telemetry/opentelemetry-collector-contrib/exporter/awsemfexporter"
	"github.com/open-telemetry/opentelemetry-collector-contrib/exporter/elasticsearchexporter"
	"github.com/open-telemetry/opentelemetry-collector-contrib/exporter/fileexporter"
	"github.com/open-telemetry/opentelemetry-collector-contrib/exporter/influxdbexporter"
	"github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusexporter"
	"github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusremotewriteexporter"
	"github.com/open-telemetry/opentelemetry-collector-contrib/processor/metricstransformprocessor"
	"github.com/open-telemetry/opentelemetry-collector-contrib/processor/resourcedetectionprocessor"
	"github.com/open-telemetry/opentelemetry-collector-contrib/processor/resourceprocessor"
	"github.com/open-telemetry/opentelemetry-collector-contrib/processor/transformprocessor"

	"go.uber.org/multierr"
)

func components() (otelcol.Factories, error) {
	var errs error

	receivers, err := otelcol.MakeFactoryMap(
		otlpreceiver.NewFactory(),
		connections.NewFactory(),
		mounts.NewFactory(),
		nfsd.NewFactory(),
		fscache.NewFactory(),
		exports.NewFactory(),
		oldestfile.NewFactory(),
		slab.NewFactory(),
	)
	errs = multierr.Append(errs, err)

	processors, err := otelcol.MakeFactoryMap(
		metricstransformprocessor.NewFactory(),
		resourcedetectionprocessor.NewFactory(),
		resourceprocessor.NewFactory(),
		transformprocessor.NewFactory(),
	)
	errs = multierr.Append(errs, err)

	processors[memorylimiterprocessor.NewFactory().Type()] = memorylimiterprocessor.NewFactory()

	exporters, err := otelcol.MakeFactoryMap(
		awsemfexporter.NewFactory(),
		debugexporter.NewFactory(),
		otlpexporter.NewFactory(),
		otlphttpexporter.NewFactory(),
		elasticsearchexporter.NewFactory(),
		fileexporter.NewFactory(),
		influxdbexporter.NewFactory(),
		prometheusexporter.NewFactory(),
		prometheusremotewriteexporter.NewFactory(),
	)
	errs = multierr.Append(errs, err)

	extensions, err := otelcol.MakeFactoryMap(
		zpagesextension.NewFactory(),
	)
	errs = multierr.Append(errs, err)

	factories := otelcol.Factories{
		Receivers:  receivers,
		Processors: processors,
		Exporters:  exporters,
		Extensions: extensions,
		Telemetry:  otelconftelemetry.NewFactory(),
	}
	return factories, errs
}
