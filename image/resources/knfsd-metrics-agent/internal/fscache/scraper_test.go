/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package fscache

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseFscacheStats(t *testing.T) {
	t.Parallel()

	stats, err := parseFscacheStats("testdata/stats")
	require.NoError(t, err)

	// Verify Netfslib Reads
	assert.Equal(t, uint64(100), stats.Reads.DR)
	assert.Equal(t, uint64(200), stats.Reads.RA)
	assert.Equal(t, uint64(300), stats.Reads.RF)
	assert.Equal(t, uint64(50), stats.Reads.RS)
	assert.Equal(t, uint64(400), stats.Reads.WB)
	assert.Equal(t, uint64(500), stats.Reads.WBZ)

	// Verify Netfslib Writes
	assert.Equal(t, uint64(10), stats.Writes.BW)
	assert.Equal(t, uint64(20), stats.Writes.WT)
	assert.Equal(t, uint64(30), stats.Writes.DW)
	assert.Equal(t, uint64(40), stats.Writes.WP)
	assert.Equal(t, uint64(50), stats.Writes.C2)

	// Verify Netfslib ZeroOps
	assert.Equal(t, uint64(5), stats.ZeroOps.ZR)
	assert.Equal(t, uint64(6), stats.ZeroOps.Sh)
	assert.Equal(t, uint64(7), stats.ZeroOps.Sk)

	// Verify Netfslib DownOps
	assert.Equal(t, uint64(1000), stats.DownOps.DL)
	assert.Equal(t, uint64(990), stats.DownOps.Ds)
	assert.Equal(t, uint64(10), stats.DownOps.Df)
	assert.Equal(t, uint64(5), stats.DownOps.Di)

	// Verify Netfslib CaRdOps
	assert.Equal(t, uint64(500), stats.CaRdOps.RD)
	assert.Equal(t, uint64(490), stats.CaRdOps.Rs)
	assert.Equal(t, uint64(10), stats.CaRdOps.Rf)

	// Verify Netfslib UpldOps
	assert.Equal(t, uint64(200), stats.UpldOps.UL)
	assert.Equal(t, uint64(195), stats.UpldOps.Us)
	assert.Equal(t, uint64(5), stats.UpldOps.Uf)

	// Verify Netfslib CaWrOps
	assert.Equal(t, uint64(300), stats.CaWrOps.WR)
	assert.Equal(t, uint64(295), stats.CaWrOps.Ws)
	assert.Equal(t, uint64(5), stats.CaWrOps.Wf)

	// Verify Netfslib Retries
	assert.Equal(t, uint64(2), stats.Retries.Rq)
	assert.Equal(t, uint64(3), stats.Retries.Rs)
	assert.Equal(t, uint64(1), stats.Retries.Wq)
	assert.Equal(t, uint64(2), stats.Retries.Ws)

	// Verify Netfslib Objs
	assert.Equal(t, uint64(1000), stats.Objs.Rr)
	assert.Equal(t, uint64(2000), stats.Objs.Sr)
	assert.Equal(t, uint64(500), stats.Objs.Foq)
	assert.Equal(t, uint64(10), stats.Objs.Wsc)

	// Verify Netfslib WbLock
	assert.Equal(t, uint64(50), stats.WbLock.Skip)
	assert.Equal(t, uint64(25), stats.WbLock.Wait)

	// Verify FS-Cache Cookies
	assert.Equal(t, uint64(1000), stats.Cookies.N)
	assert.Equal(t, uint64(50), stats.Cookies.V)
	assert.Equal(t, uint64(2), stats.Cookies.Vcol)
	assert.Equal(t, uint64(1), stats.Cookies.Voom)

	// Verify FS-Cache Acquire
	assert.Equal(t, uint64(1050), stats.Acquire.N)
	assert.Equal(t, uint64(1048), stats.Acquire.Ok)
	assert.Equal(t, uint64(2), stats.Acquire.Oom)

	// Verify FS-Cache LRU
	assert.Equal(t, uint64(500), stats.LRU.N)
	assert.Equal(t, uint64(100), stats.LRU.Exp)
	assert.Equal(t, uint64(200), stats.LRU.Rmv)
	assert.Equal(t, uint64(50), stats.LRU.Drp)

	// Verify FS-Cache Invals
	assert.Equal(t, uint64(10), stats.Invals.N)

	// Verify FS-Cache Updates
	assert.Equal(t, uint64(100), stats.Updates.N)
	assert.Equal(t, uint64(20), stats.Updates.Rsz)
	assert.Equal(t, uint64(5), stats.Updates.Rsn)

	// Verify FS-Cache Relinqs
	assert.Equal(t, uint64(200), stats.Relinqs.N)
	assert.Equal(t, uint64(50), stats.Relinqs.Rtr)
	assert.Equal(t, uint64(10), stats.Relinqs.Drop)

	// Verify FS-Cache NoSpace
	assert.Equal(t, uint64(5), stats.NoSpace.Nwr)
	assert.Equal(t, uint64(3), stats.NoSpace.Ncr)
	assert.Equal(t, uint64(100), stats.NoSpace.Cull)

	// Verify FS-Cache IO
	assert.Equal(t, uint64(10000), stats.IO.Rd)
	assert.Equal(t, uint64(5000), stats.IO.Wr)
	assert.Equal(t, uint64(10), stats.IO.Mis)
}

func TestParseFscacheStatsZeros(t *testing.T) {
	t.Parallel()

	stats, err := parseFscacheStats("testdata/stats_zeros")
	require.NoError(t, err)

	// Verify all values are zero
	assert.Equal(t, uint64(0), stats.Reads.DR)
	assert.Equal(t, uint64(0), stats.Reads.RA)
	assert.Equal(t, uint64(0), stats.Reads.RF)
	assert.Equal(t, uint64(0), stats.Reads.RS)
	assert.Equal(t, uint64(0), stats.Reads.WB)
	assert.Equal(t, uint64(0), stats.Reads.WBZ)
	assert.Equal(t, uint64(0), stats.Writes.BW)
	assert.Equal(t, uint64(0), stats.Writes.WT)
	assert.Equal(t, uint64(0), stats.Writes.DW)
	assert.Equal(t, uint64(0), stats.Writes.WP)
	assert.Equal(t, uint64(0), stats.Writes.C2)
	assert.Equal(t, uint64(0), stats.ZeroOps.ZR)
	assert.Equal(t, uint64(0), stats.ZeroOps.Sh)
	assert.Equal(t, uint64(0), stats.ZeroOps.Sk)
	assert.Equal(t, uint64(0), stats.DownOps.DL)
	assert.Equal(t, uint64(0), stats.DownOps.Ds)
	assert.Equal(t, uint64(0), stats.DownOps.Df)
	assert.Equal(t, uint64(0), stats.DownOps.Di)
	assert.Equal(t, uint64(0), stats.CaRdOps.RD)
	assert.Equal(t, uint64(0), stats.CaRdOps.Rs)
	assert.Equal(t, uint64(0), stats.CaRdOps.Rf)
	assert.Equal(t, uint64(0), stats.UpldOps.UL)
	assert.Equal(t, uint64(0), stats.UpldOps.Us)
	assert.Equal(t, uint64(0), stats.UpldOps.Uf)
	assert.Equal(t, uint64(0), stats.CaWrOps.WR)
	assert.Equal(t, uint64(0), stats.CaWrOps.Ws)
	assert.Equal(t, uint64(0), stats.CaWrOps.Wf)
	assert.Equal(t, uint64(0), stats.Retries.Rq)
	assert.Equal(t, uint64(0), stats.Retries.Rs)
	assert.Equal(t, uint64(0), stats.Retries.Wq)
	assert.Equal(t, uint64(0), stats.Retries.Ws)
	assert.Equal(t, uint64(0), stats.Objs.Rr)
	assert.Equal(t, uint64(0), stats.Objs.Sr)
	assert.Equal(t, uint64(0), stats.Objs.Foq)
	assert.Equal(t, uint64(0), stats.Objs.Wsc)
	assert.Equal(t, uint64(0), stats.WbLock.Skip)
	assert.Equal(t, uint64(0), stats.WbLock.Wait)
	assert.Equal(t, uint64(0), stats.Cookies.N)
	assert.Equal(t, uint64(0), stats.Cookies.V)
	assert.Equal(t, uint64(0), stats.Cookies.Vcol)
	assert.Equal(t, uint64(0), stats.Cookies.Voom)
	assert.Equal(t, uint64(0), stats.Acquire.N)
	assert.Equal(t, uint64(0), stats.Acquire.Ok)
	assert.Equal(t, uint64(0), stats.Acquire.Oom)
	assert.Equal(t, uint64(0), stats.LRU.N)
	assert.Equal(t, uint64(0), stats.LRU.Exp)
	assert.Equal(t, uint64(0), stats.LRU.Rmv)
	assert.Equal(t, uint64(0), stats.LRU.Drp)
	assert.Equal(t, uint64(0), stats.Invals.N)
	assert.Equal(t, uint64(0), stats.Updates.N)
	assert.Equal(t, uint64(0), stats.Updates.Rsz)
	assert.Equal(t, uint64(0), stats.Updates.Rsn)
	assert.Equal(t, uint64(0), stats.Relinqs.N)
	assert.Equal(t, uint64(0), stats.Relinqs.Rtr)
	assert.Equal(t, uint64(0), stats.Relinqs.Drop)
	assert.Equal(t, uint64(0), stats.NoSpace.Nwr)
	assert.Equal(t, uint64(0), stats.NoSpace.Ncr)
	assert.Equal(t, uint64(0), stats.NoSpace.Cull)
	assert.Equal(t, uint64(0), stats.IO.Rd)
	assert.Equal(t, uint64(0), stats.IO.Wr)
	assert.Equal(t, uint64(0), stats.IO.Mis)
}

func TestParseFscacheStatsEmpty(t *testing.T) {
	t.Parallel()

	stats, err := parseFscacheStats("testdata/stats_empty")
	require.NoError(t, err)

	// All values should be zero (default)
	assert.Equal(t, uint64(0), stats.Reads.DR)
	assert.Equal(t, uint64(0), stats.Cookies.N)
	assert.Equal(t, uint64(0), stats.IO.Rd)
}

func TestParseFscacheStatsFileNotFound(t *testing.T) {
	t.Parallel()

	_, err := parseFscacheStats("testdata/nonexistent")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to open fscache stats file")
}

func TestParseFscacheStatsDirectoryNotFound(t *testing.T) {
	t.Parallel()

	_, err := parseFscacheStats("testdata/nonexistent/stats")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to open fscache stats file")
}

func TestParseKeyValues(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		input    string
		expected map[string]uint64
	}{
		{
			name:  "simple values",
			input: " DR=100 RA=200 RF=300",
			expected: map[string]uint64{
				"DR": 100,
				"RA": 200,
				"RF": 300,
			},
		},
		{
			name:  "values with zeros",
			input: " n=0 v=0 vcol=0 voom=0",
			expected: map[string]uint64{
				"n":    0,
				"v":    0,
				"vcol": 0,
				"voom": 0,
			},
		},
		{
			name:  "2C key (starts with number)",
			input: " BW=10 WT=20 DW=30 WP=40 2C=50",
			expected: map[string]uint64{
				"BW": 10,
				"WT": 20,
				"DW": 30,
				"WP": 40,
				"2C": 50,
			},
		},
		{
			name:     "empty string",
			input:    "",
			expected: map[string]uint64{},
		},
		{
			name:  "malformed entry skipped",
			input: " valid=100 invalid 2C=50",
			expected: map[string]uint64{
				"valid": 100,
				"2C":    50,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := parseKeyValues(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestParseLine(t *testing.T) {
	t.Parallel()

	stats := &fscacheStats{}

	// Test Reads line
	err := parseLine("Reads  : DR=100 RA=200 RF=300 RS=50 WB=400 WBZ=500", stats)
	require.NoError(t, err)
	assert.Equal(t, uint64(100), stats.Reads.DR)
	assert.Equal(t, uint64(200), stats.Reads.RA)
	assert.Equal(t, uint64(50), stats.Reads.RS)

	// Test Writes line with 2C
	err = parseLine("Writes : BW=10 WT=20 DW=30 WP=40 2C=50", stats)
	require.NoError(t, err)
	assert.Equal(t, uint64(50), stats.Writes.C2)

	// Test LRU line (should skip "at")
	err = parseLine("LRU    : n=500 exp=100 rmv=200 drp=50 at=12345", stats)
	require.NoError(t, err)
	assert.Equal(t, uint64(500), stats.LRU.N)
	assert.Equal(t, uint64(100), stats.LRU.Exp)

	// Test invalid line format
	err = parseLine("InvalidLineWithoutColon", stats)
	require.Error(t, err)
}
