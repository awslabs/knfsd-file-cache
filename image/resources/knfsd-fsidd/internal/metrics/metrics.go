/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package metrics

import (
	"context"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

var meter = otel.Meter("fsid")

var (
	dimensionless = metric.WithUnit("1")
	milliseconds  = metric.WithUnit("ms")
)

var (
	requestCount    = counter("fsid.request.count", dimensionless)
	requestDuration = duration("fsid.request.duration", milliseconds)
	requestRetries  = int64Histogram("fsid.request.retries", dimensionless)

	operationCount    = counter("fsid.operation.count", dimensionless)
	operationDuration = duration("fsid.operation.duration", milliseconds)

	sqlQueryCount    = counter("fsid.sql.query.count", dimensionless)
	sqlQueryDuration = duration("fsid.sql.query.duration", milliseconds)
)

func Request(ctx context.Context, command, result string, retries int64, duration time.Duration) {
	attrs := []attribute.KeyValue{
		attribute.String("command", command),
		attribute.String("result", result),
	}
	requestCount.Add(ctx, 1, metric.WithAttributes(attrs...))
	requestDuration.Record(ctx, ms(duration), metric.WithAttributes(attrs...))
	requestRetries.Record(ctx, retries, metric.WithAttributes(attrs...))
}

func Operation(ctx context.Context, command, result string, retry int64, duration time.Duration) {
	attrs := []attribute.KeyValue{
		attribute.String("command", command),
		attribute.String("result", result),
		attribute.Int64("retry", retry),
	}
	operationCount.Add(ctx, 1, metric.WithAttributes(attrs...))
	operationDuration.Record(ctx, ms(duration), metric.WithAttributes(attrs...))
}

func SQLOperation(ctx context.Context, query, result string, duration time.Duration) {
	attrs := []attribute.KeyValue{
		attribute.String("query", query),
		attribute.String("result", result),
	}
	sqlQueryCount.Add(ctx, 1, metric.WithAttributes(attrs...))
	sqlQueryDuration.Record(ctx, ms(duration), metric.WithAttributes(attrs...))
}

func counter(name string, opts ...metric.Int64CounterOption) metric.Int64Counter {
	m, err := meter.Int64Counter(name, opts...)
	if err != nil {
		otel.Handle(err)
	}
	return m
}

func duration(name string, opts ...metric.Float64HistogramOption) metric.Float64Histogram {
	m, err := meter.Float64Histogram(name, opts...)
	if err != nil {
		otel.Handle(err)
	}
	return m
}

func int64Histogram(name string, opts ...metric.Int64HistogramOption) metric.Int64Histogram {
	m, err := meter.Int64Histogram(name, opts...)
	if err != nil {
		otel.Handle(err)
	}
	return m
}

func ms(duration time.Duration) float64 {
	return float64(duration) / float64(time.Millisecond)
}
