/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	sdkretry "github.com/aws/aws-sdk-go-v2/aws/retry"
	"github.com/aws/smithy-go"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/log"
	"github.com/googleapis/gax-go/v2"
)

// Retry layering: the AWS SDK's standard retryer already performs
// per-request exponential backoff with jitter for transient faults
// (throttling, HTTP 5xx, connection errors). The withRetry/withRetryDeadline
// loop below sits above the SDK and provides a wall-clock budget across
// whole operations, covering longer infrastructure blips than the SDK's
// per-request attempt limit, plus the application-level conflict-reread
// convergence used by get_or_create_fsidnum.

// defaultRetryDeadline bounds the per-call retry window for steady-state
// callers (socket handlers). Long enough to ride out short infrastructure
// blips (STS throttling, DynamoDB internal errors, brief network partitions)
// without returning errors to the kernel NFS client, but short enough that a
// genuine outage eventually surfaces.
const defaultRetryDeadline = 5 * time.Minute

// withRetry retries fn using defaultRetryDeadline as the wall-clock budget.
// Suitable for steady-state callers that need to tolerate longer transient
// infrastructure blips.
func withRetry(ctx context.Context, fn func() error) error {
	return withRetryDeadline(ctx, defaultRetryDeadline, fn)
}

// withRetryDeadline retries fn until it succeeds or the given wall-clock
// budget is exhausted. Use this for boot-time paths (e.g. CheckTable) where
// a tight budget is preferred so that the process exits promptly on repeated
// failure and systemd's Restart= loop takes over; this gives the AWS control
// plane (IAM / STS) additional wall-clock time to re-propagate credentials
// between process restarts.
func withRetryDeadline(ctx context.Context, budget time.Duration, fn func() error) error {
	deadline := time.Now().Add(budget)
	backoff := &gax.Backoff{
		// Because of jitter, this will pick a time between 1ns and Interval
		// Keeping the initial interval small as the kernel is waiting for this
		// response. Though not too small otherwise it's likely to cause another
		// collision and have to retry again.
		Initial:    50 * time.Millisecond,
		Max:        60 * time.Second,
		Multiplier: 2,
	}

	// Keep retrying until the deadline is reached.
	var err error
	for {
		// Not interrupting an attempt once it has started, the deadline only
		// applies to the sleep/retry loop.
		err = fn()
		if err == nil {
			return nil
		}
		if !ShouldRetry(err) {
			return err
		}

		pause := backoff.Pause()
		// Check there's enough time remaining before the deadline for another attempt.
		if !time.Now().Add(pause).Before(deadline) {
			return err
		}

		log.Debug.Printf("[%d] RETRY (%s): %v", log.ID(ctx), pause, err)

		// Allow sleep to be interrupted by the context being cancelled to allow
		// for graceful shutdown.
		err = sleep(ctx, pause)
		if err != nil {
			return err
		}
	}
}

func sleep(ctx context.Context, d time.Duration) error {
	if d < 1 {
		return nil
	}

	t := time.NewTimer(d)
	defer t.Stop()

	select {
	case <-t.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// retryableErrorCodes lists DynamoDB API error codes that are worth retrying
// at the application level, in addition to the AWS SDK's own retryable
// classification (which already covers throttling, HTTP 5xx and transport
// errors). The SDK retries these per-request; classifying them here lets the
// wall-clock budget keep trying beyond the SDK's per-request attempt limit.
var retryableErrorCodes = map[string]struct{}{
	// throttling / capacity
	"ThrottlingException":                    {},
	"ProvisionedThroughputExceededException": {},
	"RequestLimitExceeded":                   {},
	"LimitExceededException":                 {},

	// transient service faults
	"InternalServerError": {},
	"ServiceUnavailable":  {},

	// transactional conflicts, the transaction was cancelled so try again
	"TransactionConflictException":   {},
	"TransactionInProgressException": {},

	// auth errors
	"AccessDeniedException":       {},
	"ExpiredTokenException":       {},
	"UnrecognizedClientException": {},
}

func ShouldRetry(err error) bool {
	if err == nil {
		return false
	}
	// ErrNotFound is not retried, it is used by get_fsid and get_path to
	// signal that there is no record to return.
	if IsNotFound(err) {
		return false
	}
	// Conflicts are retryable: get_or_create_fsidnum re-reads the mapping
	// allocated by the winning process and converges.
	if IsConflict(err) {
		return true
	}
	// Defer to the AWS SDK's standard retryable classification for
	// connection errors, HTTP 5xx responses and throttling codes.
	if sdkRetryable(err) {
		return true
	}

	if apiErr, ok := errors.AsType[smithy.APIError](err); ok {
		_, retry := retryableErrorCodes[apiErr.ErrorCode()]
		return retry
	}
	return false
}

// sdkRetryable reports whether the AWS SDK's default retryable checks
// (connection errors, retryable HTTP status codes, throttling error codes)
// classify err as retryable.
func sdkRetryable(err error) bool {
	retryables := sdkretry.IsErrorRetryables(sdkretry.DefaultRetryables)
	return retryables.IsErrorRetryable(err) == aws.TrueTernary
}
