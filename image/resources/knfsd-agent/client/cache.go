/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package client

type CacheUsageResponse struct {
	BytesTotal     uint64 `json:"bytesTotal"`
	BytesUsed      uint64 `json:"bytesUsed"`
	BytesFree      uint64 `json:"bytesFree"`
	BytesAvailable uint64 `json:"bytesAvailable"`

	BlockSize       int64  `json:"blockSize"`
	BlocksTotal     uint64 `json:"blocksTotal"`
	BlocksUsed      uint64 `json:"blocksUsed"`
	BlocksFree      uint64 `json:"blocksFree"`
	BlocksAvailable uint64 `json:"blocksAvailable"`

	FilesTotal uint64 `json:"filesTotal"`
	FilesUsed  uint64 `json:"filesUsed"`
	FilesFree  uint64 `json:"filesFree"`
}

func (c *KnfsdAgentClient) CacheUsage() (*CacheUsageResponse, error) {
	var v *CacheUsageResponse
	err := c.get("api/v1/cache/usage", &v)
	return v, err
}
