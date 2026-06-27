/*
	Copyright 2023 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/ec2/imds"
)

// QueryAttribute reads an EC2 instance tag through IMDSv2. The Terraform
// configuration tags the test client with "knfsd-file-cache:source-host" and
// "knfsd-file-cache:proxy-host" which the smoke-test driver maps to the
// well-known short names "source_host" / "proxy_host".
func QueryAttribute(name string) (string, error) {
	tag := mapTagName(name)

	value, err := getMetadataValue("tags/instance/" + tag)
	if err != nil {
		return "", fmt.Errorf("IMDSv2 tag %s: %w", tag, err)
	}

	return strings.TrimSpace(value), nil
}

// getMetadataValue fetches a metadata path from the AWS Instance Metadata Service (IMDSv2)
// returning the output as a string.
func getMetadataValue(uri string) (string, error) {
	ctx := context.Background()

	// Create a default AWS configuration
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return "", err
	}

	// Create an IMDS client, disable default 5s timeout
	client := imds.NewFromConfig(cfg, func(options *imds.Options) {
		options.DisableDefaultTimeout = true
	})

	// Create new context from previous ctx with a custom 2s timeout
	// https://docs.aws.amazon.com/sdk-for-go/v2/developer-guide/configure-retries-timeouts.html#timeouts
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	// Fetch the metadata value
	output, err := client.GetMetadata(ctx, &imds.GetMetadataInput{
		Path: uri,
	})
	if err != nil {
		return "", err
	}

	defer output.Content.Close()
	bytes, err := io.ReadAll(output.Content)
	if err != nil {
		return "", err
	}

	return string(bytes), nil
}

func mapTagName(name string) string {
	switch name {
	case "source_host":
		return "knfsd-file-cache:source-host"
	case "proxy_host":
		return "knfsd-file-cache:proxy-host"
	default:
		return name
	}
}
