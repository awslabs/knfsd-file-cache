/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testTable = "knfsd-fsids-test"

// fakeDynamoDB starts an HTTP server standing in for the DynamoDB endpoint,
// and returns an FSIDSource connected to it with static dummy credentials.
// The handler receives a channel closed during cleanup, so handlers that
// never respond (blackhole) can be released before the server shuts down.
func fakeDynamoDB(t *testing.T, handler func(stop <-chan struct{}) http.HandlerFunc) FSIDSource {
	t.Helper()
	stop := make(chan struct{})
	srv := httptest.NewServer(handler(stop))
	t.Cleanup(func() {
		close(stop)
		srv.Close()
	})

	client := dynamodb.New(dynamodb.Options{
		Region:       "eu-west-1",
		BaseEndpoint: aws.String(srv.URL),
		Credentials:  credentials.NewStaticCredentialsProvider("fsid", "fsid", ""),
		// The fake responses do not include an x-amz-crc32 header.
		DisableValidateResponseChecksum: true,
	})
	return FSIDSource{client: client, tableName: testTable}
}

// apiError returns a handler replying with a DynamoDB JSON error response.
func apiError(status int, code, message string) func(<-chan struct{}) http.HandlerFunc {
	return func(<-chan struct{}) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			_, _ = io.Copy(io.Discard, r.Body)
			w.Header().Set("Content-Type", "application/x-amz-json-1.0")
			w.WriteHeader(status)
			_, _ = fmt.Fprintf(w, `{"__type":"com.amazonaws.dynamodb.v20120810#%s","message":%q}`, code, message)
		}
	}
}

// blackhole accepts the request but never responds, simulating a missing
// route to DynamoDB (connections that hang rather than being refused).
func blackhole(stop <-chan struct{}) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-r.Context().Done():
		case <-stop:
		}
	}
}

// TestCheckTable_Unreachable is the regression test for knfsd-fsidd being
// killed by the systemd start timeout when DynamoDB is unreachable. The
// in-flight attempt must be bounded so the call returns within its budget
// with an actionable error, rather than "context canceled".
func TestCheckTable_Unreachable(t *testing.T) {
	t.Parallel()
	s := fakeDynamoDB(t, blackhole)
	budget := 2 * time.Second

	start := time.Now()
	err := s.checkTable(context.Background(), budget, 300*time.Millisecond)
	elapsed := time.Since(start)

	require.Error(t, err)
	assert.Less(t, elapsed, budget+time.Second, "checkTable exceeded its budget (elapsed=%s)", elapsed)
	assert.NotErrorIs(t, err, context.Canceled)
	assert.Contains(t, err.Error(), "cannot reach the DynamoDB endpoint")
	assert.Contains(t, err.Error(), testTable)
}

func TestCheckTable_AccessDenied(t *testing.T) {
	t.Parallel()
	s := fakeDynamoDB(t, apiError(http.StatusBadRequest, "AccessDeniedException",
		"User is not authorized to perform: dynamodb:DescribeTable"))
	budget := time.Second

	start := time.Now()
	err := s.checkTable(context.Background(), budget, 300*time.Millisecond)
	elapsed := time.Since(start)

	require.Error(t, err)
	assert.Less(t, elapsed, budget+time.Second, "checkTable exceeded its budget (elapsed=%s)", elapsed)
	assert.Contains(t, err.Error(), "not authorised")
	apiErr, ok := errors.AsType[smithy.APIError](err)
	require.True(t, ok, "expected the underlying API error to be wrapped")
	assert.Equal(t, "AccessDeniedException", apiErr.ErrorCode())
}

func TestCheckTable_TableNotFound(t *testing.T) {
	t.Parallel()
	s := fakeDynamoDB(t, apiError(http.StatusBadRequest, "ResourceNotFoundException",
		"Requested resource not found"))

	start := time.Now()
	err := s.checkTable(context.Background(), 5*time.Second, time.Second)
	elapsed := time.Since(start)

	require.Error(t, err)
	// ResourceNotFoundException is not retried, so fail fast.
	assert.Less(t, elapsed, time.Second, "checkTable retried a permanent error (elapsed=%s)", elapsed)
	assert.Contains(t, err.Error(), "not found in region")
	_, ok := errors.AsType[*types.ResourceNotFoundException](err)
	assert.True(t, ok, "expected the underlying ResourceNotFoundException to be wrapped")
}

// TestCheckTable_ParentCancelled verifies a SIGTERM during boot is reported
// as a cancellation, not misreported as a connectivity problem.
func TestCheckTable_ParentCancelled(t *testing.T) {
	t.Parallel()
	s := fakeDynamoDB(t, blackhole)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	err := s.checkTable(ctx, 5*time.Second, 2*time.Second)

	require.Error(t, err)
	assert.NotContains(t, err.Error(), "cannot reach")
}

func TestCheckTable_OK(t *testing.T) {
	t.Parallel()
	s := fakeDynamoDB(t, func(<-chan struct{}) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			_, _ = io.Copy(io.Discard, r.Body)
			w.Header().Set("Content-Type", "application/x-amz-json-1.0")
			_, _ = fmt.Fprintf(w, `{"Table":{"TableName":%q,"TableStatus":"ACTIVE"}}`, testTable)
		}
	})

	assert.NoError(t, s.checkTable(context.Background(), time.Second, 300*time.Millisecond))
}

func TestCheckTableHint(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		err  error
		want string
	}{
		{
			name: "AttemptTimeout",
			err:  fmt.Errorf("%w: %w", errAttemptTimeout, context.DeadlineExceeded),
			want: "cannot reach the DynamoDB endpoint",
		},
		{
			name: "RequestSendError",
			err:  &smithyhttp.RequestSendError{Err: errors.New("dial tcp: i/o timeout")},
			want: "cannot reach the DynamoDB endpoint",
		},
		{
			name: "AccessDenied",
			err:  &smithy.GenericAPIError{Code: "AccessDeniedException"},
			want: "not authorised",
		},
		{
			name: "UnrecognizedClient",
			err:  &smithy.GenericAPIError{Code: "UnrecognizedClientException"},
			want: "not authorised",
		},
		{
			name: "ResourceNotFound",
			err:  &types.ResourceNotFoundException{Message: aws.String("not found")},
			want: "not found in region",
		},
		{
			name: "Throttling",
			err:  &smithy.GenericAPIError{Code: "ThrottlingException"},
			want: "throttling",
		},
		{
			name: "InternalServerError",
			err:  &types.InternalServerError{Message: aws.String("boom")},
			want: "temporarily unavailable",
		},
		{
			name: "Unknown",
			err:  &smithy.GenericAPIError{Code: "ValidationException"},
			want: "unexpected DynamoDB error",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, checkTableHint(testTable, "eu-west-1", tc.err), tc.want)
		})
	}
}
