/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package convert

import (
	"math"
	"testing"
)

func TestInt64(t *testing.T) {
	testCases := []struct {
		name     string
		input    uint64
		expected int64
	}{
		{
			name:     "Maximum int64 value",
			input:    math.MaxInt64,
			expected: math.MaxInt64,
		},
		{
			name:     "Overflow by 1",
			input:    math.MaxInt64 + 1,
			expected: 0,
		},
		{
			name:     "Overflow by 2",
			input:    math.MaxInt64 + 2,
			expected: 1,
		},
		{
			name:     "Maximum uint64 value",
			input:    math.MaxUint64,
			expected: math.MaxInt64 % (math.MaxInt64 + 1),
		},
		{
			name:     "Zero value",
			input:    0,
			expected: 0,
		},
		{
			name:     "Small positive value",
			input:    42,
			expected: 42,
		},
		{
			name:     "Large value overflowing max int64",
			input:    math.MaxInt64 + math.MaxInt64/2,
			expected: (math.MaxInt64 + math.MaxInt64/2) % (math.MaxInt64 + 1),
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := Int64(tc.input)
			if result != tc.expected {
				t.Errorf("Int64(%d): expected %d, got %d",
					tc.input, tc.expected, result)
			}
		})
	}
}

// Benchmark the conversion function
func BenchmarkInt64(b *testing.B) {
	testValue := uint64(math.MaxInt64 + 42)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		Int64(testValue)
	}
}
