/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/smithy-go"
	"github.com/stretchr/testify/assert"
)

func TestShouldRetry(t *testing.T) {
	t.Run("ErrNotFound", func(t *testing.T) {
		t.Parallel()
		// ErrNotFound should not be retried, as this is used by get_fsid and
		// get_path to signal that there's no record to return.
		assert.False(t, ShouldRetry(ErrNotFound))
	})

	t.Run("ErrConflict", func(t *testing.T) {
		t.Parallel()
		// Conflicts are retryable so that get_or_create_fsidnum re-reads the
		// mapping allocated by the winning process and converges.
		assert.True(t, ShouldRetry(ErrConflict))
		assert.True(t, ShouldRetry(fmt.Errorf("%w: path %q", ErrConflict, "/foo")))
	})

	t.Run("Throttling", func(t *testing.T) {
		t.Parallel()
		err := &smithy.GenericAPIError{
			Code:    "ThrottlingException",
			Message: "Rate of requests exceeds the allowed throughput",
		}
		assert.True(t, ShouldRetry(err))
	})

	t.Run("InternalServerError", func(t *testing.T) {
		t.Parallel()
		err := &types.InternalServerError{
			Message: aws.String("Internal server error"),
		}
		assert.True(t, ShouldRetry(err))
	})

	t.Run("TransactionConflict", func(t *testing.T) {
		t.Parallel()
		// Item-level transaction conflicts are transient, the cancelled
		// transaction can simply be retried.
		err := &types.TransactionConflictException{
			Message: aws.String("Transaction is ongoing for the item"),
		}
		assert.True(t, ShouldRetry(err))
	})

	t.Run("AccessDenied", func(t *testing.T) {
		t.Parallel()
		// AccessDeniedException is retryable to tolerate IAM policy
		// propagation races on fresh deployments (the DynamoDB policy
		// attached to the EC2 instance role can take up to ~60 s to
		// propagate).
		err := &smithy.GenericAPIError{
			Code:    "AccessDeniedException",
			Message: "User is not authorized to perform dynamodb:GetItem",
		}
		assert.True(t, ShouldRetry(err))
	})

	t.Run("ValidationException", func(t *testing.T) {
		t.Parallel()
		// Permanent client errors must not be retried.
		err := &smithy.GenericAPIError{
			Code:    "ValidationException",
			Message: "One or more parameter values were invalid",
		}
		assert.False(t, ShouldRetry(err))
	})

	t.Run("ResourceNotFound", func(t *testing.T) {
		t.Parallel()
		// A missing table is a permanent misconfiguration, not a transient
		// fault. (Boot-time IAM propagation is covered by
		// AccessDeniedException instead.)
		err := &types.ResourceNotFoundException{
			Message: aws.String("Requested resource not found"),
		}
		assert.False(t, ShouldRetry(err))
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
		return &smithy.GenericAPIError{Code: "ThrottlingException"}
	}

	start := time.Now()
	err := withRetryDeadline(context.Background(), budget, alwaysFail)
	elapsed := time.Since(start)

	assert.Error(t, err, "expected withRetryDeadline to return the last error after budget is exhausted")
	// Allow a generous upper bound to avoid flakes on slow CI, but still
	// prove the function does not loop for minutes.
	assert.Less(t, elapsed, 2*time.Second, "withRetryDeadline exceeded budget (elapsed=%s)", elapsed)
}
