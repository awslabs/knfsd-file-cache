/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package nfsd

import (
	"testing"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent/convert"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParsePoolStats(t *testing.T) {
	t.Parallel()

	pools, err := parsePoolStats("testdata/pool_stats")
	require.NoError(t, err)
	require.Len(t, pools, 1)

	assert.Equal(t, 0, pools[0].Pool)
	assert.Equal(t, uint64(100), pools[0].PacketsArrived)
	assert.Equal(t, uint64(5), pools[0].SocketsEnqueued)
	assert.Equal(t, uint64(90), pools[0].ThreadsWoken)
	assert.Equal(t, uint64(2), pools[0].ThreadsTimedout)
}

func TestParsePoolStatsMultiplePools(t *testing.T) {
	t.Parallel()

	pools, err := parsePoolStats("testdata/pool_stats_multiple")
	require.NoError(t, err)
	require.Len(t, pools, 2)

	// Pool 0
	assert.Equal(t, 0, pools[0].Pool)
	assert.Equal(t, uint64(100), pools[0].PacketsArrived)
	assert.Equal(t, uint64(5), pools[0].SocketsEnqueued)
	assert.Equal(t, uint64(90), pools[0].ThreadsWoken)
	assert.Equal(t, uint64(2), pools[0].ThreadsTimedout)

	// Pool 1
	assert.Equal(t, 1, pools[1].Pool)
	assert.Equal(t, uint64(200), pools[1].PacketsArrived)
	assert.Equal(t, uint64(10), pools[1].SocketsEnqueued)
	assert.Equal(t, uint64(180), pools[1].ThreadsWoken)
	assert.Equal(t, uint64(4), pools[1].ThreadsTimedout)
}

func TestParsePoolStatsEmpty(t *testing.T) {
	t.Parallel()

	pools, err := parsePoolStats("testdata/pool_stats_empty")
	require.NoError(t, err)
	assert.Len(t, pools, 0)
}

func TestParsePoolStatsZeros(t *testing.T) {
	t.Parallel()

	pools, err := parsePoolStats("testdata/pool_stats_zeros")
	require.NoError(t, err)
	require.Len(t, pools, 1)

	assert.Equal(t, 0, pools[0].Pool)
	assert.Equal(t, uint64(0), pools[0].PacketsArrived)
	assert.Equal(t, uint64(0), pools[0].SocketsEnqueued)
	assert.Equal(t, uint64(0), pools[0].ThreadsWoken)
	assert.Equal(t, uint64(0), pools[0].ThreadsTimedout)
}

func TestParsePoolStatsFileNotFound(t *testing.T) {
	t.Parallel()

	_, err := parsePoolStats("testdata/nonexistent")
	require.Error(t, err)
}

func TestPacketsDeferredCalculation(t *testing.T) {
	t.Parallel()

	// Test case: arrived=100, enqueued=5, woken=90
	// deferred = 100 - (5 + 90) = 5
	arrived := uint64(100)
	enqueued := uint64(5)
	woken := uint64(90)

	var deferred int64
	if arrived >= (enqueued + woken) {
		deferred = convert.Int64(arrived - (enqueued + woken))
	}

	assert.Equal(t, int64(5), deferred)
}

func TestPacketsDeferredCalculationWithMultiplePools(t *testing.T) {
	t.Parallel()

	pools, err := parsePoolStats("testdata/pool_stats_multiple")
	require.NoError(t, err)

	// Aggregate stats from all pools
	var totalPacketsArrived uint64
	var totalSocketsEnqueued uint64
	var totalThreadsWoken uint64

	for _, pool := range pools {
		totalPacketsArrived += pool.PacketsArrived
		totalSocketsEnqueued += pool.SocketsEnqueued
		totalThreadsWoken += pool.ThreadsWoken
	}

	// Pool 0: arrived=100, enqueued=5, woken=90
	// Pool 1: arrived=200, enqueued=10, woken=180
	// Total: arrived=300, enqueued=15, woken=270
	// deferred = 300 - (15 + 270) = 15
	assert.Equal(t, uint64(300), totalPacketsArrived)
	assert.Equal(t, uint64(15), totalSocketsEnqueued)
	assert.Equal(t, uint64(270), totalThreadsWoken)

	var packetsDeferred int64
	if totalPacketsArrived >= (totalSocketsEnqueued + totalThreadsWoken) {
		packetsDeferred = convert.Int64(totalPacketsArrived - (totalSocketsEnqueued + totalThreadsWoken))
	}

	assert.Equal(t, int64(15), packetsDeferred)
}
