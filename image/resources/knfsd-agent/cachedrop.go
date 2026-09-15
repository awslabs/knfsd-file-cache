/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-agent/client"
	"golang.org/x/sys/unix"
)

// dropCachesPath is the kernel knob that frees clean caches. See
// proc_sys_vm(5) for the accepted values.
const dropCachesPath = "/proc/sys/vm/drop_caches"

// handleCacheDrop frees the kernel caches, so a caller can force subsequent
// reads to come from FS-Cache (L2) rather than the page cache (L1). Used by the
// smoke tests to prove the cache is actually serving reads.
func handleCacheDrop(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		// Safe to return verbatim; it describes the request, not the server.
		writeCacheDropError(w, r, http.StatusMethodNotAllowed,
			"method not allowed, use POST", nil)
		return
	}

	mode, err := parseDropCachesMode(r.URL.Query().Get("mode"))
	if err != nil {
		// Validation messages are derived from the caller's own input, so
		// returning them leaks nothing and makes the API usable.
		writeCacheDropError(w, r, http.StatusBadRequest, err.Error(), err)
		return
	}

	if err := dropCaches(mode); err != nil {
		// Internal failures return a generic message and log the detail,
		// matching JSONHandlerFunc.Execute.
		writeCacheDropError(w, r, http.StatusInternalServerError,
			"An unknown error occurred", err)
		return
	}

	body, err := json.MarshalIndent(&client.CacheDropResponse{Mode: mode}, "", "  ")
	if err != nil {
		writeCacheDropError(w, r, http.StatusInternalServerError,
			"An unknown error occurred", err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write(body); err != nil { // nosemgrep
		log.Printf("Failed to write cache drop response: %s", err.Error())
		return
	}

	logRequest(r, http.StatusOK, nil)
}

// parseDropCachesMode validates the requested mode against the values
// proc_sys_vm(5) defines, defaulting to 3 when unset:
//
//	1  free pagecache
//	2  free dentries and inodes
//	3  free pagecache, dentries and inodes
//
// The result is written to a procfs file, so this is an allowlist rather than a
// range check; nothing outside these three values is ever passed through.
func parseDropCachesMode(raw string) (int, error) {
	if raw == "" {
		return client.DropCachesAll, nil
	}

	switch raw {
	case "1":
		return client.DropCachesPageCache, nil
	case "2":
		return client.DropCachesSlab, nil
	case "3":
		return client.DropCachesAll, nil
	default:
		return 0, fmt.Errorf("invalid mode %q, must be 1, 2 or 3", raw)
	}
}

// dropCaches syncs then writes the mode to /proc/sys/vm/drop_caches.
//
// The sync is required, not cosmetic: proc_sys_vm(5) notes that dirty objects
// are not freeable and that callers should sync first. Without it the drop is
// only partial, which would let a cache-read assertion pass for the wrong
// reason.
func dropCaches(mode int) error {
	unix.Sync()

	// #nosec G306 -- procfs knob, permissions are fixed by the kernel
	if err := os.WriteFile(dropCachesPath, fmt.Appendf(nil, "%d\n", mode), 0); err != nil {
		return fmt.Errorf("failed to write %s: %w", dropCachesPath, err)
	}
	return nil
}

// writeCacheDropError logs cause (which may hold detail that must not reach the
// client) and returns message to the caller.
func writeCacheDropError(w http.ResponseWriter, r *http.Request, statusCode int, message string, cause error) {
	if cause == nil {
		cause = fmt.Errorf("%s", message)
	}
	logRequest(r, statusCode, cause)

	body, err := json.MarshalIndent(&client.ErrorResponse{Message: message}, "", "  ")
	if err != nil {
		http.Error(w, "failed to encode error response", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if _, err := w.Write(body); err != nil { // nosemgrep
		log.Printf("Failed to write cache drop error response: %s", err.Error())
	}
}
