/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"net/http"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-agent/client"
	"golang.org/x/sys/unix"
)

func handleCacheUsage(*http.Request) (*client.CacheUsageResponse, error) {
	var s unix.Statfs_t
	err := unix.Statfs("/var/cache/fscache", &s)
	if err != nil {
		return nil, err
	}

	bs := uint64(s.Bsize) // #nosec G115
	return &client.CacheUsageResponse{
		BytesTotal:     s.Blocks * bs,
		BytesUsed:      (s.Blocks - s.Bfree) * bs,
		BytesFree:      s.Bfree * bs,
		BytesAvailable: s.Bavail * bs,

		BlockSize:       s.Bsize,
		BlocksTotal:     s.Blocks,
		BlocksUsed:      s.Blocks - s.Bfree,
		BlocksFree:      s.Bfree,
		BlocksAvailable: s.Bavail,

		FilesTotal: s.Files,
		FilesUsed:  s.Files - s.Ffree,
		FilesFree:  s.Ffree,
	}, nil
}
