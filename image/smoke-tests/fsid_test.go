/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package smoke_tests

import (
	"context"
	"strconv"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// checkFSIDTable validates the DynamoDB FSID table deployed by the proxy
// module (FSID_MODE = "external"). By this point the remote smoke tests have
// mounted and exercised the proxy export, so mountd must have resolved at
// least one FSID through knfsd-fsidd.
//
// It validates the invariants documented in deployment/database/README.md:
//   - a COUNTER item exists holding the next FSID to allocate
//   - PATH#/FSID# items form a consistent bijection
//   - FSIDs are dense sequential integers starting at 1 (gap-free)
//   - re-querying each mapping returns the identical FSID (stability)
func checkFSIDTable(ctx context.Context, t *testing.T, region, tableName string) {
	require.NotEmpty(t, tableName, "fsid_table_name output was empty")

	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	require.NoError(t, err)
	client := dynamodb.NewFromConfig(cfg)

	// Read the entire table; it only contains a handful of items (one
	// PATH#/FSID# pair per export, plus the COUNTER item).
	var items []map[string]types.AttributeValue
	paginator := dynamodb.NewScanPaginator(client, &dynamodb.ScanInput{
		TableName:      aws.String(tableName),
		ConsistentRead: aws.Bool(true),
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		require.NoError(t, err)
		items = append(items, page.Items...)
	}

	var nextFSID int64
	var counterFound bool
	paths := map[string]int64{} // PATH#<path> => fsid
	fsids := map[int64]string{} // FSID#<n>    => path

	for _, item := range items {
		id := stringAttr(t, item, "id")
		switch {
		case id == "COUNTER":
			counterFound = true
			nextFSID = numberAttr(t, item, "next_fsid")

		case strings.HasPrefix(id, "PATH#"):
			paths[strings.TrimPrefix(id, "PATH#")] = numberAttr(t, item, "fsid")

		case strings.HasPrefix(id, "FSID#"):
			fsid, err := strconv.ParseInt(strings.TrimPrefix(id, "FSID#"), 10, 64)
			require.NoError(t, err)
			fsids[fsid] = stringAttr(t, item, "path")

		default:
			t.Errorf("unexpected item %q in FSID table %q", id, tableName)
		}
	}

	// mountd resolved at least one export, so at least one FSID must have
	// been allocated and the counter created.
	require.True(t, counterFound, "COUNTER item missing from FSID table %q", tableName)
	require.NotEmpty(t, paths, "no PATH# items in FSID table %q", tableName)

	// The PATH#/FSID# items must form a consistent bijection.
	require.Len(t, fsids, len(paths), "PATH# and FSID# item counts differ")
	for path, fsid := range paths {
		assert.Equal(t, path, fsids[fsid], "PATH#/FSID# mismatch for fsid %d", fsid)
	}

	// FSIDs are allocated as dense sequential integers starting at 1, and
	// the counter always holds the next FSID to hand out (gap-free).
	assert.EqualValues(t, len(paths), nextFSID-1,
		"COUNTER next_fsid=%d does not match %d allocated FSIDs", nextFSID, len(paths))
	for fsid := int64(1); fsid < nextFSID; fsid++ {
		assert.Contains(t, fsids, fsid, "gap in FSID space: FSID#%d missing", fsid)
	}

	// Stability: re-querying each mapping must return the identical FSID.
	for path, fsid := range paths {
		out, err := client.GetItem(ctx, &dynamodb.GetItemInput{
			TableName: aws.String(tableName),
			Key: map[string]types.AttributeValue{
				"id": &types.AttributeValueMemberS{Value: "PATH#" + path},
			},
			ConsistentRead: aws.Bool(true),
		})
		require.NoError(t, err)
		require.NotNil(t, out.Item, "PATH#%s disappeared on re-query", path)
		assert.Equal(t, fsid, numberAttr(t, out.Item, "fsid"),
			"FSID for path %q changed on re-query", path)
	}
}

func stringAttr(t *testing.T, item map[string]types.AttributeValue, name string) string {
	t.Helper()
	attr, ok := item[name].(*types.AttributeValueMemberS)
	require.True(t, ok, "attribute %q missing or not a string", name)
	return attr.Value
}

func numberAttr(t *testing.T, item map[string]types.AttributeValue, name string) int64 {
	t.Helper()
	attr, ok := item[name].(*types.AttributeValueMemberN)
	require.True(t, ok, "attribute %q missing or not a number", name)
	n, err := strconv.ParseInt(attr.Value, 10, 64)
	require.NoError(t, err)
	return n
}
