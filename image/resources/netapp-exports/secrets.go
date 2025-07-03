/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"
	"unicode/utf8"

	mw "github.com/aws/aws-sdk-go-v2/aws/middleware"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/smithy-go/middleware"
)

type AWSSecret struct {
	Region  string `hcl:"region,optional"`
	Name    string `hcl:"name"`
	Version string `hcl:"version,optional"`
}

var secretData struct {
	SecretString string `json:"secret"`
}

func (s *AWSSecret) validate() error {
	if s.Name == "" {
		return errors.New("name required for AWS Secret")
	}
	return nil
}

func (s *AWSSecret) get(ctx context.Context) (string, error) {
	// Create AWS configuration with explicit AWS region and custom user agent
	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(s.Region),
		config.WithAPIOptions([]func(*middleware.Stack) error{
			mw.AddUserAgentKeyValue("knfsd-file-cache/netapp-exports", version),
			mw.AddUserAgentKeyValue("AWSSOLUTION/SO9129", version),
		}),
	)
	if err != nil {
		return "", fmt.Errorf("failed to load AWS configuration: %w", err)
	}

	svc := secretsmanager.NewFromConfig(cfg)

	if s.Version == "" {
		s.Version = "AWSCURRENT"
	}

	input := &secretsmanager.GetSecretValueInput{
		SecretId:     &s.Name,
		VersionStage: &s.Version,
	}

	// add 5 sec timeout
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	result, err := svc.GetSecretValue(ctx, input)
	if err != nil {
		return "", fmt.Errorf("error getting secret value for '%s': %w", s.Name, err)
	}

	if result.SecretString == nil {
		return "", fmt.Errorf("'%s' did not contain any data", s.Name)
	}

	err = json.Unmarshal([]byte(*result.SecretString), &secretData)
	if err != nil {
		return "", fmt.Errorf("error unmarshaling secret value for '%s': %w", s.Name, err)
	}

	secretString := secretData.SecretString
	if !utf8.Valid([]byte(secretString)) {
		return "", fmt.Errorf("'%s' is not valid UTF8", s.Name)
	}

	return secretString, nil
}
