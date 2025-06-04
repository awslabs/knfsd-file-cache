/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"log"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/confmap"
	"go.opentelemetry.io/collector/confmap/provider/envprovider"
	"go.opentelemetry.io/collector/confmap/provider/fileprovider"
	"go.opentelemetry.io/collector/confmap/provider/yamlprovider"
	"go.opentelemetry.io/collector/otelcol"
)

var version string

func main() {
	providers := []confmap.ProviderFactory{
		envprovider.NewFactory(),
		fileprovider.NewFactory(),
		yamlprovider.NewFactory(),
	}

	params := otelcol.CollectorSettings{
		BuildInfo: component.BuildInfo{
			Command:     "knfsd-metrics-agent",
			Description: "KNFSD Metrics Agent",
			Version:     version,
		},
		Factories: components,
		ConfigProviderSettings: otelcol.ConfigProviderSettings{
			ResolverSettings: confmap.ResolverSettings{
				ProviderFactories: providers,
				DefaultScheme:     "env",
			},
		},
	}

	cmd := otelcol.NewCommand(params)
	err := cmd.Execute()
	if err != nil {
		log.Fatalln(err)
	}
}
