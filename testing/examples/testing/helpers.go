/*
	Copyright 2024 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package testing

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/gruntwork-io/terratest/modules/gcp"
	"github.com/gruntwork-io/terratest/modules/logger"
	scope "github.com/gruntwork-io/terratest/modules/test-structure"
)

func GetTestID(t TestingT, testFolder string) string {
	path := scope.FormatTestDataPath(testFolder, "test-id")
	path = filepath.Clean(path)

	if bytes, err := os.ReadFile(path); err == nil {
		id := strings.TrimSpace(string(bytes))
		if id != "" {
			logger.Default.Logf(t, "Using existing TestID \"%s\"", id)
			return id
		}
	} else if !os.IsNotExist(err) {
		t.Fatalf("Failed to read %s: %v", path, err)
	}

	id := gcp.RandomValidGcpName()
	bytes := []byte(id)
	logger.Default.Logf(t, "Created new TestID \"%s\"", id)

	parentDir := filepath.Dir(path)
	if err := os.MkdirAll(parentDir, 0750); err != nil {
		t.Fatalf("Failed to create folder %s: %v", parentDir, err)
	}

	if err := os.WriteFile(path, bytes, 0600); err != nil {
		t.Fatalf("Failed to save value %s: %v", path, err)
	}

	return id
}

func FindVarFiles(name string) ([]string, error) {
	var err error
	names := []string{
		"terraform.tfvars",
		name + ".tfvars",
	}
	paths := make([]string, 0, len(names))

	for _, n := range names {
		paths, err = appendVarFile(paths, n)
		if err != nil {
			return nil, err
		}
	}

	return paths, nil
}

func appendVarFile(paths []string, name string) ([]string, error) {
	name, err := resolveVarFile(name)
	if err != nil {
		if os.IsNotExist(err) {
			return paths, nil
		} else {
			return paths, err
		}
	} else {
		paths = append(paths, name)
		return paths, nil
	}
}

func resolveVarFile(name string) (string, error) {
	_, err := os.Stat(name)
	if err != nil {
		return "", err
	}
	return filepath.Abs(name)
}
