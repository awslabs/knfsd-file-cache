/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCombineMultiline(t *testing.T) {
	tests := [][2]string{
		{"", ""},
		{"\n", ""},
		{"\n\n", ""},
		{"\r", ""},
		{"\r\r", ""},
		{"\n\r\n", ""},

		{"172.31.74.7", "172.31.74.7"},
		{"default", "default"},
		{"sg-1e680277", "sg-1e680277"},

		{"172.31.74.7\n172.31.64.10\n172.31.75.6", "172.31.74.7,172.31.64.10,172.31.75.6"},
		{"default\nssh\ncaching", "default,ssh,caching"},
		{"sg-1e680277\nsg-04fabc4c405b76359", "sg-1e680277,sg-04fabc4c405b76359"},
	}

	for _, x := range tests {
		x := x
		t.Run(x[0], func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, x[1], combineMultiline(x[0]))
		})
	}
}
