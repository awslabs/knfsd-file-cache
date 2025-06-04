/*
	Copyright 2023 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net/http"
)

func QueryAttribute(name string) (string, error) {
	url := fmt.Sprintf("http://metadata.google.internal/computeMetadata/v1/instance/attributes/%s?alt=text", name)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return "", nil
	}

	req.Header.Add("Metadata-Flavor", "Google")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		return "", errors.New(res.Status)
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return "", err
	}

	return string(bytes.TrimSpace(body)), nil
}
