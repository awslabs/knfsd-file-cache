/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fragmentation

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/collector/consumer/consumertest"
	"go.opentelemetry.io/collector/receiver/receivertest"
)

func TestCreateMetricsReceiver(t *testing.T) {
	t.Parallel()

	factory := NewFactory()
	cfg := factory.CreateDefaultConfig()

	receiver, err := factory.CreateMetrics(
		context.Background(),
		receivertest.NewNopSettings(factory.Type()),
		cfg,
		consumertest.NewNop(),
	)
	require.NoError(t, err)
	assert.NotNil(t, receiver)
}

func TestCreateMetricsReceiverWrongConfig(t *testing.T) {
	t.Parallel()

	factory := NewFactory()
	_, err := createMetricsReceiver(
		context.Background(),
		receivertest.NewNopSettings(factory.Type()),
		nil,
		consumertest.NewNop(),
	)
	assert.ErrorIs(t, err, errWrongConfig)
}

func TestDefaultConfig(t *testing.T) {
	t.Parallel()

	cfg, ok := NewFactory().CreateDefaultConfig().(*Config)
	require.True(t, ok)

	assert.Equal(t, "/var/cache/fscache/cache", cfg.CachePath)
	assert.Equal(t, int64(1024*1024), cfg.MinFileSize)

	// Walking the cache is expensive, so this must scrape less often than the
	// /proc based receivers.
	assert.Equal(t, 10*time.Minute, cfg.CollectionInterval)

	// The scrape is bounded so it cannot overrun the collection interval, and
	// building from NewDefaultControllerConfig() means InitialDelay is
	// populated rather than left at its zero value.
	assert.Equal(t, 2*time.Minute, cfg.Timeout)
	assert.NotZero(t, cfg.InitialDelay)
}

func TestValidate(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		cachePath   string
		minFileSize int64
		wantErr     bool
	}{
		{name: "valid", cachePath: "/var/cache/fscache/cache", minFileSize: 1024, wantErr: false},
		{name: "zero min file size", cachePath: "/tmp", minFileSize: 0, wantErr: false},
		{name: "empty cache path", cachePath: "", minFileSize: 1024, wantErr: true},
		{name: "negative min file size", cachePath: "/tmp", minFileSize: -1, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			c := Config{CachePath: tt.cachePath, MinFileSize: tt.minFileSize}
			if tt.wantErr {
				assert.Error(t, c.Validate())
			} else {
				assert.NoError(t, c.Validate())
			}
		})
	}
}
