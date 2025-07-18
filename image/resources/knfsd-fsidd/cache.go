/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"sync"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/log"
)

// FSIDCache provides a simple read cache to improve read performance by avoiding
// querying the remote database for fsids that have already been resolved by
// previous requests.
// If there are concurrent requests to get or allocate an FSID, let those
// requests race each other. Concurrency and consistency will be handled by the
// database.
type FSIDCache struct {
	source FSIDProvider
	fsids  sync.Map // path => fsid
	paths  sync.Map // fsid => path
}

func (c *FSIDCache) GetFSID(ctx context.Context, path string) (int32, error) {
	if fsid, ok := c.fsids.Load(path); ok {
		log.Debug.Printf("cache hit: GetFSID path=%s fsid=%d", path, fsid.(int32))
		return fsid.(int32), nil
	}
	log.Debug.Printf("cache miss: GetFSID path=%s, querying database", path)
	fsid, err := c.source.GetFSID(ctx, path)
	if err == nil {
		log.Debug.Printf("cache store: GetFSID path=%s fsid=%d", path, fsid)
		c.store(fsid, path)
	}
	return fsid, err
}

func (c *FSIDCache) AllocateFSID(ctx context.Context, path string) (int32, error) {
	if fsid, ok := c.fsids.Load(path); ok {
		log.Debug.Printf("cache hit: AllocateFSID path=%s fsid=%d", path, fsid.(int32))
		return fsid.(int32), nil
	}
	log.Debug.Printf("cache miss: AllocateFSID path=%s, querying database", path)
	fsid, err := c.source.AllocateFSID(ctx, path)
	if err == nil {
		log.Debug.Printf("cache store: AllocateFSID path=%s fsid=%d", path, fsid)
		c.store(fsid, path)
	}
	return fsid, err
}

func (c *FSIDCache) GetPath(ctx context.Context, fsid int32) (string, error) {
	if path, ok := c.paths.Load(fsid); ok {
		log.Debug.Printf("cache hit: GetPath fsid=%d path=%s", fsid, path.(string))
		return path.(string), nil
	}
	log.Debug.Printf("cache miss: GetPath fsid=%d, querying database", fsid)
	path, err := c.source.GetPath(ctx, fsid)
	if err == nil {
		log.Debug.Printf("cache store: GetPath fsid=%d path=%s", fsid, path)
		c.store(fsid, path)
	}
	return path, err
}

func (c *FSIDCache) store(fsid int32, path string) {
	// Concurrent requests will all result in the same fsid, path pair so just
	// blindly store the results.
	// There may be some initial contention on the keys but that will quickly
	// resolve itself, after which the fsid/path combination will be readonly.
	c.fsids.Store(path, fsid)
	c.paths.Store(fsid, path)
}
