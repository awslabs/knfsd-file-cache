/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package client

type OSResponse struct {
	Kernel string            `json:"kernel"`
	OS     map[string]string `json:"os"`
}

func (c *KnfsdAgentClient) GetOS() (*OSResponse, error) {
	var v *OSResponse
	err := c.get("api/v1/os", &v)
	return v, err
}
