/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"path"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseConfig(t *testing.T) {
	c := parseTestConfig(t, "basic.hcl")
	assert.Len(t, c.Servers, 3)

	t.Run("basic-attributes", func(t *testing.T) {
		t.Parallel()
		s := findServer(t, c, "basic-attributes")
		assert.Equal(t, "https://10.0.0.2:8080", s.URL)
		assert.Equal(t, "knfsd", s.User)
		assert.Equal(t, "secret", s.Password)

		// even though we did not set a TLS block, the TLS block should still
		// have a default value
		assert.NotNil(t, s.TLS)
		assert.Equal(t, "", s.TLS.CACertificate)
		assert.Equal(t, false, s.TLS.AllowCommonName)
		assert.Equal(t, false, s.TLS.insecure)
	})

	t.Run("tls", func(t *testing.T) {
		t.Parallel()
		s := findServer(t, c, "tls")
		require.NotNil(t, s.TLS)
		assert.Equal(t, "NetApp CA Certificate", s.TLS.CACertificate)
		assert.Equal(t, true, s.TLS.AllowCommonName)
		assert.Equal(t, false, s.TLS.insecure)
	})

	t.Run("empty-tls", func(t *testing.T) {
		t.Parallel()
		s := findServer(t, c, "empty-tls")
		require.NotNil(t, s.TLS)
		assert.Equal(t, "", s.TLS.CACertificate)
		assert.Equal(t, false, s.TLS.AllowCommonName)
		assert.Equal(t, false, s.TLS.insecure)
	})
}

func TestParseConfig_AWSSecret(t *testing.T) {
	c := parseTestConfig(t, "aws_secret.hcl")
	assert.Len(t, c.Servers, 4)

	t.Run("all-attributes", func(t *testing.T) {
		t.Parallel()
		s := findAWSSecret(t, c, "all-attributes")
		assert.Equal(t, "eu-west-2", s.Region)
		assert.Equal(t, "netapp-password", s.Name)
		assert.Equal(t, "AWSCURRENT", s.Version)
	})

	t.Run("minimal", func(t *testing.T) {
		t.Parallel()
		s := findAWSSecret(t, c, "minimal")
		assert.Equal(t, "netapp-password", s.Name)
		assert.Equal(t, "", s.Version)
	})

	t.Run("previous-version", func(t *testing.T) {
		t.Parallel()
		s := findAWSSecret(t, c, "previous-version")
		assert.Equal(t, "netapp-password", s.Name)
		assert.Equal(t, "AWSPREVIOUS", s.Version)
	})

	t.Run("remote-secret", func(t *testing.T) {
		t.Parallel()
		s := findAWSSecret(t, c, "remote-secret")
		assert.Equal(t, "us-east-1", s.Region)
		assert.Equal(t, "password", s.Name)
	})
}

func parseTestConfig(t *testing.T, name string) *Config {
	t.Helper()

	baseDir := "testdata/config"
	file := path.Join(baseDir, name)

	c, err := parseConfigFile(file)
	require.NoError(t, err)

	return c
}

func findServer(t *testing.T, c *Config, host string) *NetAppServer {
	t.Helper()
	for _, s := range c.Servers {
		if s.Host == host {
			return s
		}
	}
	require.Fail(t, "could not find server "+host)
	return nil
}

func findAWSSecret(t *testing.T, c *Config, name string) *AWSSecret {
	t.Helper()
	s := findServer(t, c, name)
	require.NotNil(t, s.SecurePassword)
	require.NotNil(t, s.SecurePassword.AWSSecret)
	return s.SecurePassword.AWSSecret
}
