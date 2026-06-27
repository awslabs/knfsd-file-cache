/*
	Copyright 2023 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package smoke_tests

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	scope "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/require"
)

const sshUser = "ubuntu"

func TestEnv(t *testing.T) {
	env := os.Environ()
	for _, e := range env {
		if strings.HasPrefix(e, "SKIP_") {
			fmt.Println(e)
		}
	}
}

func TestSmoke(t *testing.T) {
	defer scope.RunTestStage(t, "destroy", func() {
		terraformOptions := scope.LoadTerraformOptions(t, "terraform")
		terraform.DestroyContext(t, context.Background(), terraformOptions)
	})

	scope.RunTestStage(t, "check", func() {
		// Verify remote.test exists if running the check stage before running
		// apply. Otherwise we might just waste time running a costly apply only
		// for check to immediately fail.
		require.FileExists(t, "./remote.test")
	})

	scope.RunTestStage(t, "apply", func() {
		ctx := t.Context()
		terraformOptions := &terraform.Options{
			TerraformDir: "terraform",
			Vars: map[string]any{
				"PREFIX": fmt.Sprintf("knfsd-smoke-%s", strings.ToLower(random.UniqueID())),
			},
		}

		scope.SaveTerraformOptionsIfNotPresent(t, "terraform", terraformOptions)
		terraformOptions = scope.LoadTerraformOptions(t, "terraform")

		terraform.InitContext(t, ctx, terraformOptions)
		terraform.ApplyContext(t, ctx, terraformOptions)
	})

	scope.RunTestStage(t, "check", func() {
		ctx := t.Context()
		terraformOptions := scope.LoadTerraformOptions(t, "terraform")
		outputs := Outputs(terraform.OutputAllContext(t, ctx, terraformOptions))

		region := outputs.Region(t)
		instanceID := outputs.ClientInstanceID(t)

		// Terraform apply returns once the instance state is "running", which is
		// well before the SSM agent has registered and before the startup script
		// has finished. Wait for the agent to report Online, then gate on the
		// "knfsd-file-cache:status=ready" tag so we don't race the startup script
		// (e.g. mounting NFS before the mount helper exists). These polls return
		// immediately once satisfied, so they are also a cheap no-op when "check"
		// runs as a separate invocation after the instance is already ready.
		d := 5 * time.Minute
		terraformOptions.Logger.Logf(t, "Waiting up to %s for client SSM agent to report [online]", d)
		require.NoError(t, waitInstanceOnline(ctx, region, instanceID, d))

		r := 5 * time.Minute
		terraformOptions.Logger.Logf(t, "Waiting up to %s for client startup to report [ready]", r)
		require.NoError(t, waitInstanceReady(ctx, region, instanceID, r))

		// Push a single ephemeral key and reuse one multiplexed SSM tunnel
		// for both the scp and the ssh below.
		keyPath, cleanup, err := sendEphemeralKey(ctx, region, instanceID, sshUser)
		require.NoError(t, err)
		defer cleanup()

		controlDir, err := os.MkdirTemp("", "ssm-ssh-cm-")
		require.NoError(t, err)
		defer os.RemoveAll(controlDir)
		controlPath := filepath.Join(controlDir, "cm.sock")

		copyRemote(ctx, t, region, instanceID, keyPath, controlPath)
		executeRemote(ctx, t, region, instanceID, keyPath, controlPath)
	})
}

func copyRemote(ctx context.Context, t *testing.T, region, instanceID, keyPath, controlPath string) {
	args := proxyArgs(region, keyPath, controlPath)
	args = append(args,
		"./remote.test",
		fmt.Sprintf("%s@%s:./remote.test", sshUser, instanceID),
	)
	shell.RunCommandContext(t, ctx, &shell.Command{
		Command: "scp",
		Args:    args,
	})
}

func executeRemote(ctx context.Context, t *testing.T, region, instanceID, keyPath, controlPath string) {
	args := proxyArgs(region, keyPath, controlPath)
	args = append(args,
		fmt.Sprintf("%s@%s", sshUser, instanceID),
		"sudo ./remote.test",
	)
	shell.RunCommandContext(t, ctx, &shell.Command{
		Command: "ssh",
		Args:    args,
	})
}

type Outputs map[string]any

func (o Outputs) ClientInstanceID(t *testing.T) string {
	return o.GetString(t, "client_instance_id")
}

func (o Outputs) Region(t *testing.T) string {
	return o.GetString(t, "region")
}

func (o Outputs) GetString(t *testing.T, key string) string {
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
