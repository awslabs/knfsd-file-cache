/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/confmap"
	"go.opentelemetry.io/collector/confmap/provider/envprovider"
	"go.opentelemetry.io/collector/confmap/provider/fileprovider"
	"go.opentelemetry.io/collector/confmap/provider/yamlprovider"
	"go.opentelemetry.io/collector/otelcol"
)

// TestConfigValidates loads the shipped configs exactly as the systemd units do
// and runs the collector's own validation, so a breaking change in an upstream
// component's configuration (for example a feature gate promoted to beta) fails
// here instead of crash-looping the agent on boot.
func TestConfigValidates(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("AWS_REGION", "us-east-1")
	t.Setenv("AWS_EC2_METADATA_DISABLED", "true")
	t.Setenv("AWS_CONFIG_FILE", filepath.Join(dir, "config"))
	t.Setenv("AWS_SHARED_CREDENTIALS_FILE", filepath.Join(dir, "credentials"))
	t.Setenv("AWS_PROFILE", "")

	for _, role := range []string{"proxy", "client"} {
		t.Run(role, func(t *testing.T) {
			set := otelcol.CollectorSettings{
				BuildInfo: component.NewDefaultBuildInfo(),
				Factories: components,
				ConfigProviderSettings: otelcol.ConfigProviderSettings{
					ResolverSettings: confmap.ResolverSettings{
						URIs: []string{
							"file:config/common.yaml",
							"file:config/" + role + ".yaml",
							"file:config/custom.yaml",
						},
						ProviderFactories: []confmap.ProviderFactory{
							envprovider.NewFactory(),
							fileprovider.NewFactory(),
							yamlprovider.NewFactory(),
						},
						DefaultScheme: "env",
					},
				},
			}

			col, err := otelcol.NewCollector(set)
			require.NoError(t, err)
			require.NoError(t, col.DryRun(t.Context()))
		})
	}
}
