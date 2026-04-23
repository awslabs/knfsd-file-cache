/*
	Copyright 2024 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package testing

import (
	"fmt"

	"github.com/stretchr/testify/require"
)

type Outputs map[string]any

func (o Outputs) Project(t TestingT) string {
	return o.GetString(t, "project")
}

func (o Outputs) Zone(t TestingT) string {
	return o.GetString(t, "zone")
}

func (o Outputs) Region(t TestingT) string {
	return o.GetString(t, "region")
}

func (o Outputs) ProxyMIG(t TestingT) string {
	return o.GetString(t, "proxy_instance_group")
}

func (o Outputs) GetString(t TestingT, key string) string {
	entry, ok := o[key]
	if !ok {
		require.FailNow(t, fmt.Sprintf("Required output %s was missing", key))
	}

	val, ok := entry.(string)
	if !ok {
		require.FailNow(t, fmt.Sprintf("Required output %s was not a string", key))
	}

	if val == "" {
		require.FailNow(t, fmt.Sprintf("Required output %s was empty", key))
	}

	return val
}
