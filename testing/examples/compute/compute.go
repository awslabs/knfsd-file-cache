/*
	Copyright 2024 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package compute

import (
	"examples/testing"
	"fmt"

	"github.com/gruntwork-io/terratest/modules/gcp"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/stretchr/testify/require"
)

var UseInternalIP = false
var TestSSHUser = "terratest"

type InstanceGroup struct {
	Project string
	*gcp.ZonalInstanceGroup
}

func FetchZonalInstanceGroup(t *testing.T, project, zone, name string) *InstanceGroup {
	return &InstanceGroup{
		Project:            project,
		ZonalInstanceGroup: gcp.FetchZonalInstanceGroup(t, project, zone, name),
	}
}

func (g *InstanceGroup) ForAllInstances(t *testing.T, f func(i *Instance)) {
	instances, err := g.GetInstancesE(t, g.Project)
	require.NoErrorf(t, err, "could not fetch instances for instance group %s/%s/%s", g.Project, g.Zone, g.Name)
	for _, i := range instances {
		f(&Instance{
			Project:  g.Project,
			Instance: i,
		})
	}
}

type Instance struct {
	Project string
	*gcp.Instance
}

func (i *Instance) Execute(t *testing.T, command string) string {
	var args []string
	args = append(args,
		"compute", "ssh",
		"--ssh-flag=-q",
		"--project", i.Project,
		"--zone", i.Zone,
		"--no-user-output-enabled",
	)
	if UseInternalIP {
		args = append(args, "--internal-ip")
	}
	args = append(args,
		"--command", command,
		fmt.Sprintf("%s@%s", TestSSHUser, i.Name),
	)
	cmd := shell.Command{
		Command: "gcloud",
		Args:    args,
	}
	return shell.RunCommandAndGetOutput(t, cmd)
}
