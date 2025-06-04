/*
	Copyright 2024 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"examples/compute"
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func assertMIGSize(t *testing.T, project string, instanceGroup *compute.InstanceGroup, expectedClusterSize int) {
	t.Helper()
	instances, err := instanceGroup.GetInstancesE(t, project)
	require.NoErrorf(t, err, "could not fetch instances for instance group %d", instanceGroup)
	require.Lenf(t, instances, expectedClusterSize, "expected to find %d instances", expectedClusterSize)
}

func assertServiceStatus(t *testing.T, instance *compute.Instance, serviceName string, expectedStatus string) {
	t.Helper()
	cmd := fmt.Sprintf("systemctl show -p ActiveState --value %s", serviceName)
	out := instance.Execute(t, cmd)
	assert.Equal(t, expectedStatus, strings.TrimSpace(out))
}

func assertServiceSubStatus(t *testing.T, instance *compute.Instance, serviceName string, expectedStatus string) {
	t.Helper()
	cmd := fmt.Sprintf("systemctl show -p SubState --value %s", serviceName)
	out := instance.Execute(t, cmd)
	assert.Equal(t, expectedStatus, strings.TrimSpace(out))
}
