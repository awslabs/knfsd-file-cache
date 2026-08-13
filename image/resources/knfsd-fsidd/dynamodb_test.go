//go:build test.dynamodb

/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var testEndpoint string = os.Getenv("TEST_DYNAMODB_ENDPOINT")
var errTestEndpointNotSet = errors.New("TEST_DYNAMODB_ENDPOINT not set, cannot run DynamoDB tests")

// connectTest creates a fresh, uniquely named table on the DynamoDB Local
// test instance for each test. DynamoDB Local ignores the credential values
// but the AWS SDK requires them to be present; static dummy credentials also
// guarantee the tests can never pick up real credentials from the host.
func connectTest(t *testing.T) FSIDSource {
	t.Helper()
	ctx := context.Background()

	if testEndpoint == "" {
		t.Fatal(errTestEndpointNotSet)
	}

	cfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion("us-east-1"),
		awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider("fsid", "fsid", ""),
		),
	)
	require.NoError(t, err)

	client := dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		o.BaseEndpoint = aws.String(testEndpoint)
	})

	source := FSIDSource{
		client:    client,
		tableName: "fsids-" + uuid.NewString(),
	}

	// start with a fresh table for every test, mirroring the Terraform
	// table definition in deployment/database (single string partition key)
	_, err = client.CreateTable(ctx, &dynamodb.CreateTableInput{
		TableName:   aws.String(source.tableName),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{
				AttributeName: aws.String(idAttribute),
				AttributeType: types.ScalarAttributeTypeS,
			},
		},
		KeySchema: []types.KeySchemaElement{
			{
				AttributeName: aws.String(idAttribute),
				KeyType:       types.KeyTypeHash,
			},
		},
	})
	require.NoError(t, err)

	waiter := dynamodb.NewTableExistsWaiter(client)
	err = waiter.Wait(ctx, &dynamodb.DescribeTableInput{
		TableName: aws.String(source.tableName),
	}, 30*time.Second)
	require.NoError(t, err)

	t.Cleanup(func() {
		_, err := client.DeleteTable(context.Background(), &dynamodb.DeleteTableInput{
			TableName: aws.String(source.tableName),
		})
		if err != nil {
			t.Logf("failed to delete test table %q: %v", source.tableName, err)
		}
	})

	return source
}

func TestFSIDSource(t *testing.T) {
	t.Run("CheckTable", func(t *testing.T) {
		source := connectTest(t)
		assert.NoError(t, source.CheckTable(context.Background()))
	})

	t.Run("Basic", func(t *testing.T) {
		source := connectTest(t)

		ctx := context.Background()
		allocated_fsid, err := source.AllocateFSID(ctx, "/foo")
		require.NoError(t, err)
		assert.NotEqual(t, int32(0), allocated_fsid)

		fsid, err := source.GetFSID(ctx, "/foo")
		if assert.NoError(t, err) {
			assert.Equal(t, allocated_fsid, fsid)
		}

		path, err := source.GetPath(ctx, allocated_fsid)
		if assert.NoError(t, err) {
			assert.Equal(t, "/foo", path)
		}
	})

	t.Run("Sequential", func(t *testing.T) {
		source := connectTest(t)

		// FSIDs must be dense sequential integers starting at 1 (the COUNTER
		// item is created on first allocation, preserving the fsid > 0
		// invariant relied on by the get_path handler).
		ctx := context.Background()
		for want := int32(1); want <= 3; want++ {
			fsid, err := source.AllocateFSID(ctx, uuid.NewString())
			require.NoError(t, err)
			assert.Equal(t, want, fsid)
		}
	})

	t.Run("MissingFSID", func(t *testing.T) {
		source := connectTest(t)

		path, err := source.GetPath(context.Background(), 1)
		assert.Equal(t, "", path)
		assert.ErrorIs(t, err, ErrNotFound)
	})

	t.Run("MissingPath", func(t *testing.T) {
		source := connectTest(t)

		fsid, err := source.GetFSID(context.Background(), "/foo")
		assert.Equal(t, int32(0), fsid)
		assert.ErrorIs(t, err, ErrNotFound)
	})
}

func TestAllocateFSID(t *testing.T) {
	source := connectTest(t)

	t.Run("IsConflict", func(t *testing.T) {
		ctx := context.Background()
		_, err := source.AllocateFSID(ctx, "/foo")
		require.NoError(t, err)

		_, err = source.AllocateFSID(ctx, "/foo")
		require.Error(t, err)
		require.True(t, IsConflict(err))
		require.True(t, ShouldRetry(err))
	})

	// To run this test multiple times use:
	//   ./test.sh run -run TestAllocateFSID/Race -count=X
	t.Run("Race", func(t *testing.T) {
		// Try to race multiple workers against each other all calling
		// AllocateFSID at the same time. Only one worker should be successful,
		// the remainder should all get a conditional-write conflict on the
		// PATH# item.
		const worker_count = 10

		start := sync.WaitGroup{}
		done := sync.WaitGroup{}
		start.Add(1)
		done.Add(worker_count)

		path := uuid.NewString()
		worker := func(err *error) {
			start.Wait()
			_, *err = source.AllocateFSID(context.Background(), path)
			done.Done()
		}

		errors := make([]error, worker_count)
		for i := 0; i < worker_count; i++ {
			go worker(&errors[i])
		}
		start.Done()
		done.Wait()

		// Check that all the errors were conflicts
		var unexpected []error
		for _, err := range errors {
			if err != nil && !IsConflict(err) {
				unexpected = append(unexpected, err)
			}
		}
		require.Empty(t, unexpected)

		error_count := 0
		for _, e := range errors {
			if e != nil {
				error_count++
			}
		}
		// Only one worker should succeed
		require.Equal(t, worker_count-1, error_count)

		// The allocation transaction is atomic: losing workers must not
		// consume FSIDs. The next allocation must be exactly one above the
		// winner's FSID (no gaps in the FSID space).
		ctx := context.Background()
		winner, err := source.GetFSID(ctx, path)
		require.NoError(t, err)

		next, err := source.AllocateFSID(ctx, uuid.NewString())
		require.NoError(t, err)
		require.Equal(t, winner+1, next)
	})
}
