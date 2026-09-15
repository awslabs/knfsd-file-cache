/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package client

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

type KnfsdAgentClient struct {
	c       *http.Client
	baseURL string
}

func NewKnfsdAgentClient(c *http.Client, baseURL string) *KnfsdAgentClient {
	return &KnfsdAgentClient{c, baseURL}
}

func (c *KnfsdAgentClient) get(path string, v any) error {
	url, err := url.JoinPath(c.baseURL, path)
	if err != nil {
		return err
	}

	res, err := c.c.Get(url)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	return json.NewDecoder(res.Body).Decode(v)
}

// ErrorResponse is the body returned by endpoints that report failures as JSON.
type ErrorResponse struct {
	Message string `json:"message"`
}

// post issues a POST with no request body and decodes the JSON response.
//
// Unlike get, this checks the status code. The drop endpoint rejects invalid
// input with 400, and silently decoding an error body into the success type
// would make a failed call look like it succeeded.
func (c *KnfsdAgentClient) post(path string, v any) error {
	// url.JoinPath escapes the query string, so split it off and reattach.
	base, query, hasQuery := strings.Cut(path, "?")
	u, err := url.JoinPath(c.baseURL, base)
	if err != nil {
		return err
	}
	if hasQuery {
		u += "?" + query
	}

	res, err := c.c.Post(u, "application/json", http.NoBody)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		var e ErrorResponse
		if err := json.NewDecoder(res.Body).Decode(&e); err == nil && e.Message != "" {
			return fmt.Errorf("%s: %s", res.Status, e.Message)
		}
		return fmt.Errorf("%s", res.Status)
	}

	return json.NewDecoder(res.Body).Decode(v)
}
