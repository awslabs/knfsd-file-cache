/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package client

import (
	"encoding/json"
	"net/http"
	"net/url"
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
