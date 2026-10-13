/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"fmt"
	"net"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

// errAttemptTimeout marks a single boot-time DescribeTable attempt that was
// abandoned after checkTableAttemptTimeout while the overall boot budget was
// still running. ShouldRetry treats it as retryable.
var errAttemptTimeout = errors.New("attempt timed out")

// authErrorCodes are DynamoDB API error codes caused by the instance
// credentials or IAM policy.
var authErrorCodes = map[string]struct{}{
	"AccessDeniedException":       {},
	"UnrecognizedClientException": {},
	"ExpiredTokenException":       {},
}

// transientErrorCodes are DynamoDB API error codes caused by throttling or
// temporary service faults.
var transientErrorCodes = map[string]struct{}{
	"ThrottlingException":                    {},
	"ProvisionedThroughputExceededException": {},
	"RequestLimitExceeded":                   {},
	"LimitExceededException":                 {},
	"InternalServerError":                    {},
	"ServiceUnavailable":                     {},
}

// checkTableHint describes the likely cause of a boot-time DescribeTable
// failure, and how to fix it, so that the journal points end users at the
// fix rather than only the raw AWS SDK error.
func checkTableHint(table, region string, err error) string {
	if _, ok := errors.AsType[*types.ResourceNotFoundException](err); ok {
		return fmt.Sprintf("table %q not found in region %q, "+
			"check FSID_DATABASE_CONFIG table_name and region match the deployed FSID table", table, region)
	}

	if apiErr, ok := errors.AsType[smithy.APIError](err); ok {
		if _, auth := authErrorCodes[apiErr.ErrorCode()]; auth {
			return fmt.Sprintf("the instance role is not authorised to call dynamodb:DescribeTable on table %q, "+
				"check the FSID database IAM policy (or FSID_DATABASE_IAM_POLICY, if set) is attached to the instance role, "+
				"including the role of EXISTING_INSTANCE_PROFILE_NAME, if set; IAM changes can take a short time to propagate", table)
		}
		if _, transient := transientErrorCodes[apiErr.ErrorCode()]; transient {
			return "DynamoDB is throttling requests or is temporarily unavailable"
		}
	}

	if isConnectivityError(err) {
		return fmt.Sprintf("cannot reach the DynamoDB endpoint in region %q, "+
			"check the subnet route table has a DynamoDB gateway VPC endpoint or a NAT gateway route, "+
			"and that security group and network ACL egress allow TCP 443 "+
			"(see FAQ: \"The knfsd-fsidd service cannot reach DynamoDB\")", region)
	}

	if respErr, ok := errors.AsType[interface {
		error
		HTTPStatusCode() int
	}](err); ok && respErr.HTTPStatusCode() >= 500 {
		return "DynamoDB is throttling requests or is temporarily unavailable"
	}

	return "unexpected DynamoDB error"
}

// isConnectivityError reports whether err indicates DynamoDB could not be
// reached at all (no HTTP response), as opposed to an API error response.
func isConnectivityError(err error) bool {
	if errors.Is(err, errAttemptTimeout) || errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	if _, ok := errors.AsType[*smithyhttp.RequestSendError](err); ok {
		return true
	}
	if _, ok := errors.AsType[net.Error](err); ok {
		return true
	}
	return false
}
