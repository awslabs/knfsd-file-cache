/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	mw "github.com/aws/aws-sdk-go-v2/aws/middleware"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/smithy-go/middleware"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/internal/metrics"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/log"
	"github.com/googleapis/gax-go/v2"
)

// The main purpose of this code is to provide a way to manage file system IDs
// in an Amazon DynamoDB table, allowing for the association of paths with
// unique identifiers (FSIDs) and vice versa.
//
// The table uses a single string partition key ("id") with three item types:
//
//   - "PATH#<path>"  => {fsid, path}  forward lookup (path -> fsid)
//   - "FSID#<fsid>"  => {fsid, path}  reverse lookup (fsid -> path)
//   - "COUNTER"      => {next_fsid}   allocation sequence (next FSID to hand out)
//
// AllocateFSID uses a conditional-write claim pattern inside a single
// TransactWriteItems call so that when multiple KNFSD instances race to
// allocate an FSID for the same path, exactly one writer wins and the
// remainder observe a conflict.

// bootRetryDeadline bounds the initial CheckTable retry window. Kept short
// so that if fsidd is racing IAM policy propagation on a fresh deployment,
// the process exits promptly and systemd's Restart= loop takes over (giving
// AWS IAM additional wall-clock time to replicate between process restarts).
const bootRetryDeadline = 90 * time.Second

// DynamoDB item attribute names and key prefixes.
const (
	idAttribute      = "id"
	fsidAttribute    = "fsid"
	pathAttribute    = "path"
	counterAttribute = "next_fsid"

	pathKeyPrefix = "PATH#"
	fsidKeyPrefix = "FSID#"
	counterKey    = "COUNTER"
)

var (
	// ErrNotFound indicates that no FSID mapping exists for the requested
	// path or FSID.
	ErrNotFound = errors.New("fsid mapping not found")

	// ErrConflict indicates another process has already allocated an FSID
	// for the requested path (the conditional write on the PATH# item
	// failed). Callers should re-read the mapping; withRetry handles this
	// automatically for the socket handlers.
	ErrConflict = errors.New("fsid mapping already allocated")

	// errCounterRace indicates the allocation transaction lost a race on the
	// COUNTER item (another writer allocated a different path concurrently).
	// This is internal to AllocateFSID which re-reads the counter and
	// retries the transaction.
	errCounterRace = errors.New("fsid counter contention")
)

// connect creates the DynamoDB client. Credentials are resolved by the AWS
// SDK default chain (the EC2 instance profile in production). The region is
// taken from the config file, falling back to the environment and then the
// EC2 instance metadata service (IMDS).
func connect(ctx context.Context, config DatabaseConfig) (*dynamodb.Client, error) {
	log.Debug.Printf("table-name: %v", config.TableName)
	log.Debug.Printf("region: %v", config.Region)
	log.Debug.Printf("endpoint: %v", config.Endpoint)

	opts := []func(*awsconfig.LoadOptions) error{
		awsconfig.WithAPIOptions([]func(*middleware.Stack) error{
			mw.AddUserAgentKeyValue("knfsd-file-cache/fsidd", version),
			mw.AddUserAgentKeyValue("AWSSOLUTION/SO9129", version),
		}),
	}
	if config.Region != "" {
		opts = append(opts, awsconfig.WithRegion(config.Region))
	} else {
		// Fall back to the EC2 instance region from IMDS when the region is
		// not provided by the config file or environment.
		opts = append(opts, awsconfig.WithEC2IMDSRegion())
	}

	cfg, err := awsconfig.LoadDefaultConfig(ctx, opts...)
	if err != nil {
		log.Error.Print("failed to load AWS configuration")
		return nil, err
	}
	log.Debug.Printf("resolved region: %v", cfg.Region)

	client := dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		if config.Endpoint != "" {
			// Endpoint override is only intended for testing against
			// DynamoDB Local (Docker container).
			o.BaseEndpoint = aws.String(config.Endpoint)
		}
	})
	return client, nil
}

// The FSIDSource struct is responsible for managing file system IDs (FSIDs)
// in the DynamoDB table. It provides methods for verifying the table exists
// (CheckTable), getting an FSID for a given path (GetFSID), allocating a new
// FSID for a path (AllocateFSID), and getting the path for a given FSID
// (GetPath).
type FSIDSource struct {
	client    *dynamodb.Client
	tableName string
}

// CheckTable verifies that the FSID table exists and is reachable before the
// service starts accepting requests. The table itself is provisioned by
// Terraform. Retried with a bounded boot budget to ride out IAM policy
// propagation delays on fresh deployments.
func (s FSIDSource) CheckTable(ctx context.Context) error {
	log.Debug.Printf("checking table: %q", s.tableName)
	return withRetryDeadline(ctx, bootRetryDeadline, func() error {
		_, err := s.client.DescribeTable(ctx, &dynamodb.DescribeTableInput{
			TableName: aws.String(s.tableName),
		})
		return err
	})
}

func (s FSIDSource) GetFSID(ctx context.Context, path string) (int32, error) {
	start := time.Now()
	fsid, err := s.getFSID(ctx, path)
	metrics.DBOperation(ctx, "get_fsid", DBMetricResult(err), time.Since(start))
	return fsid, err
}

func (s FSIDSource) getFSID(ctx context.Context, path string) (int32, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.tableName),
		Key: map[string]types.AttributeValue{
			idAttribute: &types.AttributeValueMemberS{Value: pathKeyPrefix + path},
		},
		ProjectionExpression: aws.String(fsidAttribute),
		// ConsistentRead removes the risk of an eventually-consistent read
		// missing a mapping allocated moments ago by another fsidd instance.
		ConsistentRead: aws.Bool(true),
	})
	if err != nil {
		return 0, err
	}
	if out.Item == nil {
		return 0, ErrNotFound
	}
	return fsidFromItem(out.Item)
}

func (s FSIDSource) GetPath(ctx context.Context, fsid int32) (string, error) {
	start := time.Now()
	path, err := s.getPath(ctx, fsid)
	metrics.DBOperation(ctx, "get_path", DBMetricResult(err), time.Since(start))
	return path, err
}

func (s FSIDSource) getPath(ctx context.Context, fsid int32) (string, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.tableName),
		Key: map[string]types.AttributeValue{
			idAttribute: &types.AttributeValueMemberS{Value: fsidKey(fsid)},
		},
		ProjectionExpression:     aws.String("#path"),
		ExpressionAttributeNames: map[string]string{"#path": pathAttribute},
		ConsistentRead:           aws.Bool(true),
	})
	if err != nil {
		return "", err
	}
	if out.Item == nil {
		return "", ErrNotFound
	}
	attr, ok := out.Item[pathAttribute].(*types.AttributeValueMemberS)
	if !ok {
		return "", fmt.Errorf("invalid %q attribute on item %q", pathAttribute, fsidKey(fsid))
	}
	return attr.Value, nil
}

func (s FSIDSource) AllocateFSID(ctx context.Context, path string) (int32, error) {
	start := time.Now()
	fsid, err := s.allocateFSID(ctx, path)
	metrics.DBOperation(ctx, "allocate_fsid", DBMetricResult(err), time.Since(start))
	return fsid, err
}

func (s FSIDSource) allocateFSID(ctx context.Context, path string) (int32, error) {
	// Losing a race on the COUNTER item (a different path being allocated
	// concurrently) is expected under fleet-wide contention; re-read the
	// counter and retry with a small backoff. Losing the race on the PATH#
	// item returns ErrConflict to the caller instead (the path already has
	// an FSID; re-reading resolves it).
	backoff := &gax.Backoff{
		Initial:    10 * time.Millisecond,
		Max:        time.Second,
		Multiplier: 2,
	}
	for {
		fsid, err := s.tryAllocateFSID(ctx, path)
		if !errors.Is(err, errCounterRace) {
			return fsid, err
		}
		log.Debug.Printf("allocate_fsid: counter contention for path=%s, retrying", path)
		if err := sleep(ctx, backoff.Pause()); err != nil {
			return 0, err
		}
	}
}

func (s FSIDSource) tryAllocateFSID(ctx context.Context, path string) (int32, error) {
	next, counterExists, err := s.nextFSID(ctx)
	if err != nil {
		return 0, err
	}
	if next > math.MaxInt32 {
		return 0, fmt.Errorf("fsid space exhausted: next fsid %d exceeds int32", next)
	}
	fsid := int32(next) // #nosec G115 -- bounds checked above

	// The COUNTER update only succeeds if the counter still holds the value
	// we just read (or still does not exist when allocating the first FSID).
	counterCondition := fmt.Sprintf("%s = :current", counterAttribute)
	values := map[string]types.AttributeValue{
		":next":    &types.AttributeValueMemberN{Value: strconv.FormatInt(next+1, 10)},
		":current": &types.AttributeValueMemberN{Value: strconv.FormatInt(next, 10)},
	}
	if !counterExists {
		counterCondition = fmt.Sprintf("attribute_not_exists(%s)", idAttribute)
		delete(values, ":current")
	}

	fsidAttr := &types.AttributeValueMemberN{Value: strconv.FormatInt(next, 10)}
	pathAttr := &types.AttributeValueMemberS{Value: path}
	notExists := aws.String(fmt.Sprintf("attribute_not_exists(%s)", idAttribute))

	// A single atomic transaction: advance the counter and claim both
	// mapping items. Either everything commits, or nothing does (no FSID
	// gaps, and PATH#/FSID# items can never diverge).
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{
				Update: &types.Update{
					TableName: aws.String(s.tableName),
					Key: map[string]types.AttributeValue{
						idAttribute: &types.AttributeValueMemberS{Value: counterKey},
					},
					UpdateExpression:          aws.String(fmt.Sprintf("SET %s = :next", counterAttribute)),
					ConditionExpression:       aws.String(counterCondition),
					ExpressionAttributeValues: values,
				},
			},
			{
				Put: &types.Put{
					TableName: aws.String(s.tableName),
					Item: map[string]types.AttributeValue{
						idAttribute:   &types.AttributeValueMemberS{Value: pathKeyPrefix + path},
						fsidAttribute: fsidAttr,
						pathAttribute: pathAttr,
					},
					ConditionExpression: notExists,
				},
			},
			{
				Put: &types.Put{
					TableName: aws.String(s.tableName),
					Item: map[string]types.AttributeValue{
						idAttribute:   &types.AttributeValueMemberS{Value: fsidKey(fsid)},
						fsidAttribute: fsidAttr,
						pathAttribute: pathAttr,
					},
					ConditionExpression: notExists,
				},
			},
		},
	})
	if err != nil {
		return 0, classifyAllocateError(err, path)
	}
	return fsid, nil
}

// nextFSID reads the COUNTER item and returns the next FSID to allocate.
// When the COUNTER item does not exist yet (fresh table) the first FSID is 1,
// preserving the fsid > 0 invariant relied on by the get_path handler.
func (s FSIDSource) nextFSID(ctx context.Context) (next int64, exists bool, err error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.tableName),
		Key: map[string]types.AttributeValue{
			idAttribute: &types.AttributeValueMemberS{Value: counterKey},
		},
		ProjectionExpression: aws.String(counterAttribute),
		ConsistentRead:       aws.Bool(true),
	})
	if err != nil {
		return 0, false, err
	}
	if out.Item == nil {
		return 1, false, nil
	}
	attr, ok := out.Item[counterAttribute].(*types.AttributeValueMemberN)
	if !ok {
		return 0, false, fmt.Errorf("invalid %q attribute on item %q", counterAttribute, counterKey)
	}
	next, err = strconv.ParseInt(attr.Value, 10, 64)
	if err != nil {
		return 0, false, fmt.Errorf("invalid %q value on item %q: %w", counterAttribute, counterKey, err)
	}
	return next, true, nil
}

// classifyAllocateError maps a TransactWriteItems failure onto the fsidd
// error taxonomy by inspecting the per-item cancellation reasons:
//
//	index 0: COUNTER update, 1: PATH# put, 2: FSID# put
func classifyAllocateError(err error, path string) error {
	canceled, ok := errors.AsType[*types.TransactionCanceledException](err)
	if !ok {
		// Transport faults, throttling, TransactionConflictException, etc.
		// are returned as-is for ShouldRetry to classify.
		return err
	}

	reasons := canceled.CancellationReasons
	if len(reasons) == 3 && conditionFailed(reasons[1]) {
		// Another process already allocated an FSID for this path.
		return fmt.Errorf("%w: path %q: %s", ErrConflict, path, err)
	}
	if len(reasons) == 3 && conditionFailed(reasons[0]) {
		// Another process advanced the counter first (different path).
		return fmt.Errorf("%w: %s", errCounterRace, err)
	}
	for _, r := range reasons {
		if r.Code != nil && *r.Code == "TransactionConflict" {
			// A concurrent transaction touched the same items mid-flight;
			// re-reading the counter and retrying resolves this.
			return fmt.Errorf("%w: %s", errCounterRace, err)
		}
	}
	if len(reasons) == 3 && conditionFailed(reasons[2]) {
		// The FSID# item exists even though the counter claimed the FSID was
		// free. The counter is out of sync with the data (e.g. manual edits
		// or a restored backup); retrying cannot resolve this.
		return fmt.Errorf("fsid table inconsistent: a %s* item already exists for a fsid the counter reported as free: %s",
			fsidKeyPrefix, err)
	}
	return err
}

func conditionFailed(r types.CancellationReason) bool {
	return r.Code != nil && *r.Code == "ConditionalCheckFailed"
}

func fsidKey(fsid int32) string {
	return fsidKeyPrefix + strconv.FormatInt(int64(fsid), 10)
}

func fsidFromItem(item map[string]types.AttributeValue) (int32, error) {
	attr, ok := item[fsidAttribute].(*types.AttributeValueMemberN)
	if !ok {
		return 0, fmt.Errorf("invalid %q attribute", fsidAttribute)
	}
	fsid, err := strconv.ParseInt(attr.Value, 10, 32)
	if err != nil {
		return 0, fmt.Errorf("invalid %q value: %w", fsidAttribute, err)
	}
	return int32(fsid), nil
}

// IsConflict and IsNotFound are helper functions that check for the fsidd
// error taxonomy ("mapping already allocated by another process" and
// "no mapping found", respectively).
func IsConflict(err error) bool {
	return errors.Is(err, ErrConflict)
}

func IsNotFound(err error) bool {
	return errors.Is(err, ErrNotFound)
}

// DBMetricResult is a function that returns a string representation of the
// database operation result (e.g., "ok", "not_found", "conflict", or
// "error") for metric purposes.
func DBMetricResult(err error) string {
	switch {
	case err == nil:
		return "ok"
	case IsNotFound(err):
		return "not_found"
	case IsConflict(err):
		return "conflict"
	default:
		return "error"
	}
}
