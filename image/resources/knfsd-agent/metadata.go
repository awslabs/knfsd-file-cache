/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"io"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/ec2/imds"
)

// getMetadataValue fetches a metadata path from the AWS Instance Metadata Service (IMDSv2)
// returning the output as a string. If multiline is set to true, it will combine
// multiline strings into a single string.
func getMetadataValue(uri string, multiline bool) (string, error) {
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

	value := string(bytes)

	if multiline {
		value = combineMultiline(value)
	}

	return value, nil
}
