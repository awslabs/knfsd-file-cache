/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fscache

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/collector/consumer/consumertest"
	"go.opentelemetry.io/collector/receiver/receivertest"
)

func TestNewFactory(t *testing.T) {
	t.Parallel()

	factory := NewFactory()
	require.NotNil(t, factory)

	cfg := factory.CreateDefaultConfig()
	require.NotNil(t, cfg)

	fscacheCfg, ok := cfg.(*Config)
	require.True(t, ok)
	assert.Equal(t, "/proc/fs/fscache/stats", fscacheCfg.StatsPath)
}

func TestCreateDefaultConfig(t *testing.T) {
	t.Parallel()

	cfg := createDefaultConfig()
	require.NotNil(t, cfg)

	fscacheCfg, ok := cfg.(*Config)
	require.True(t, ok)
	assert.Equal(t, "/proc/fs/fscache/stats", fscacheCfg.StatsPath)
}

func TestFactoryCreateMetrics(t *testing.T) {
	t.Parallel()

	factory := NewFactory()
	_, err := factory.CreateMetrics(
		context.Background(),
		receivertest.NewNopSettings(factory.Type()),
		factory.CreateDefaultConfig(),
		consumertest.NewNop(),
	)
	require.NoError(t, err)
}
