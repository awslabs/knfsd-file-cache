/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"compress/gzip"
	_ "embed"
	"encoding/json"
	"errors"
	"log"
	"net/http"
)

//go:embed favicon.ico
var favicon []byte

// JSONHandlerFunc is an adapter for functions that return either data or an
// error. The data is JSON encoded and sent as the response to the HTTP request.
//
// All JSON responses should be a JSON object (not a plain string, array, etc)
// so to keep the logic of ServeHTTP simple force the returned value to be a
// pointer. This way ServeHTTP does not need to worry about pointer vs value
// when calling json.MarshalIndent.
type JSONHandlerFunc[T any] func(*http.Request) (*T, error)

// JSONHandler is an adapter to support automatic type inference of T when
// instantiating JSONHandlerFunc[T] because Go does not support type inference
// when instantiating types.
//
// For example, to create a JSONHandlerFunc for handleNodeInfo you would need
// to specify T; `JSONHanderFunc[nodeData](handleNodeInfo)`. Using this function
// Go can infer T automatically; `JSONHandler(handleNodeInfo)`.
func JSONHandler[T any](handler JSONHandlerFunc[T]) http.Handler {
	return handler
}

func (handler JSONHandlerFunc[T]) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	statusCode, body, err := handler.Execute(r)

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Encoding", "gzip")

	w.WriteHeader(statusCode)

	// Compress the response using gzip. Metric responses such as mounts can be
	// quite large when there are many mounts, but compress well as most of the
	// body is the same JSON keys and whitespace repeated.
	// Not implementing content negotiation using the Accept-Encoding header as
	// it's not trivial and most HTTP clients support gzip.
	gz := gzip.NewWriter(w)
	defer gz.Close()
	if _, err := gz.Write(body); err != nil {
		log.Printf("Failed to write response body to gzip writer: %s", err.Error()) // #nosec G706 -- logging internal error, not user input
	}

	if err := gz.Flush(); err != nil {
		log.Printf("Failed to flush gzip writer: %s", err.Error())
	}

	logRequest(r, statusCode, err)
}

// Execute calls the handler and formats the result as JSON.
func (handler JSONHandlerFunc[T]) Execute(r *http.Request) (statusCode int, body []byte, err error) {
	statusCode = http.StatusOK

	if r.Method == http.MethodHead {
		// In case a client relies on sending a HEAD request (e.g. for CORS
		// support) just send a basic empty response.
		// We're not going to try and generate any other headers such as
		// Content-Length as many of the handlers scrape live details on
		// request, and HEAD is supposed to be cheap to call.
		return http.StatusOK, []byte{}, nil
	}

	// Endpoints only support GET requests.
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		statusCode = http.StatusMethodNotAllowed
		body = []byte("{\"message\": \"method not allowed\"}")
		err = errors.New("method not allowed")
		return statusCode, body, err
	}

	result, err := handler(r)
	if err == nil {
		if result == nil {
			// The status endpoints only deal with queries, so there's no valid
			// reason for an endpoint to return 204 No Content. Thus if a handler
			// method returns (nil, nil) then something has gone wrong.
			err = errors.New("handler did not return any content")
		} else {
			// Convert the result to json if there was no error.
			body, err = json.MarshalIndent(result, "", "  ")
		}
	}

	// If there was an error from either the handler, or JSON conversion return
	// a generic error message to the client and log the real error message.
	if err != nil {
		statusCode = http.StatusInternalServerError
		body = []byte("{\"message\": \"An unknown error occurred\"}")
	}

	return statusCode, body, err
}

// handle favicon requests via embedded ico file, cache result for 24hrs
func handleFavIcon(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "image/x-icon")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	if _, err := w.Write(favicon); err != nil { // nosemgrep
		log.Printf("Failed to write favicon: %s", err.Error())
		http.Error(w, "Failed to serve favicon", http.StatusInternalServerError)
		return
	}
}

// log all requests
func logRequest(r *http.Request, statusCode int, err error) {
	var errMsg string
	if err != nil {
		errMsg = err.Error()
	}
	log.Printf("%s %s %s %d %s", r.RemoteAddr, r.Method, r.URL, statusCode, errMsg) // #nosec G706 -- standard HTTP access logging, not user-controlled log injection
}

func registerRoutes(mux *http.ServeMux) {
	mux.Handle("/", JSONHandler(handleNodeInfo))
	mux.Handle("/favicon.ico", http.HandlerFunc(handleFavIcon))
	mux.Handle("/api/v1/cache/usage", JSONHandler(handleCacheUsage))
	mux.Handle("/api/v1/nodeInfo", JSONHandler(handleNodeInfo))
	mux.Handle("/api/v1/mounts", JSONHandler(handleMounts))
	mux.Handle("/api/v1/mountStats", JSONHandler(handleMountStats))
	mux.Handle("/api/v1/nfs/client", JSONHandler(handleNFSClientStats))
	mux.Handle("/api/v1/nfs/server", JSONHandler(handleNFSServerStats))
	mux.Handle("/api/v1/os", JSONHandler(handleOS))
	mux.Handle("/api/v1/status", JSONHandler(handleStatus))
}
