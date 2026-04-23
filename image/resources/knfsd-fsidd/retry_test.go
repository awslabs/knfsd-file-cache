/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/stretchr/testify/assert"
)

func TestShouldRetry(t *testing.T) {
	t.Run("ErrNoRows", func(t *testing.T) {
		t.Parallel()
		// ErrNoRows should not be retried, as this is used by get_fsid and
		// get_path to signal that there's no record to return.
		assert.False(t, ShouldRetry(pgx.ErrNoRows))
	})

	t.Run("PAMAuthFailure28000", func(t *testing.T) {
		t.Parallel()
		// SQLSTATE 28000 (invalid_authorization_specification) is used by RDS
		// to report IAM auth token rejection ("PAM authentication failed").
		// This is retryable to tolerate IAM policy propagation races on
		// fresh deployments.
		err := &pgconn.PgError{
			Code:    "28000",
			Message: "PAM authentication failed for user \"fsidd\"",
		}
		assert.True(t, ShouldRetry(err))
	})
}

// TestWithRetryDeadline_BoundedBudget verifies that withRetryDeadline honours
// its wall-clock budget when the underlying call always returns a retryable
// error. The test asserts the function returns promptly after the budget is
// exhausted, rather than continuing to retry indefinitely.
func TestWithRetryDeadline_BoundedBudget(t *testing.T) {
	t.Parallel()
	budget := 200 * time.Millisecond
	alwaysFail := func() error {
		return &pgconn.PgError{Code: "28000"}
	}

	start := time.Now()
	err := withRetryDeadline(context.Background(), budget, alwaysFail)
	elapsed := time.Since(start)

	assert.Error(t, err, "expected withRetryDeadline to return the last error after budget is exhausted")
	// Allow a generous upper bound to avoid flakes on slow CI, but still
	// prove the function does not loop for minutes.
	assert.Less(t, elapsed, 2*time.Second, "withRetryDeadline exceeded budget (elapsed=%s)", elapsed)
}
