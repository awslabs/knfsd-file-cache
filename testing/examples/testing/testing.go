/*
	Copyright 2024 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package testing

import (
	"testing"

	terratest "github.com/gruntwork-io/terratest/modules/testing"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type M = testing.M
type T = testing.T

// Verify that the real testing.T type is compatible with this interface
var _ TestingT = (*testing.T)(nil)

// TestingT provides an interface for testing.T that is compatible with both
// terratest and stretchr testify.
type TestingT interface {
	require.TestingT
	assert.TestingT
	terratest.TestingT
}
