/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/internal/metrics"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/log"

	"go.uber.org/multierr"
	"gopkg.in/ini.v1"
)

const (
	defaultConfigFile = "/etc/knfsd-fsidd.conf"
	defaultSocketPath = "/run/knfsd-fsidd.sock"
)

type Config struct {
	SocketPath string         `ini:"socket"`
	Database   DatabaseConfig `ini:"database"`
	Metrics    metrics.Config `ini:"metrics"`
	Debug      bool           `ini:"debug"`
	Cache      bool           `ini:"cache"`
}

type DatabaseConfig struct {
	// TableName is the Amazon DynamoDB table storing the FSID mappings.
	TableName string `ini:"table-name"`
	// Region is the AWS region hosting the DynamoDB table. When empty the
	// region is resolved from the environment, falling back to the EC2
	// instance metadata service (IMDS).
	Region string `ini:"region"`
	// Endpoint overrides the DynamoDB service endpoint URL. Only intended
	// for testing against DynamoDB Local (Docker container).
	Endpoint string `ini:"endpoint"`
}

func (cfg *Config) Validate() error {
	var err error
	err = multierr.Append(err, required("socket-path", cfg.SocketPath))
	err = multierr.Append(err, cfg.Database.Validate())
	// No validation for the metrics, if there's errors in the config then the
	// service will still start, just without metrics. Metrics are considered
	// best effort, and errors do not prevent the app from running.
	return err
}

func (cfg *DatabaseConfig) Validate() error {
	return required("table-name", cfg.TableName)
}

func readDefaultConfig(cfg *Config) error {
	err := readConfig(cfg, defaultConfigFile)
	if errors.Is(err, os.ErrNotExist) {
		// if config file does not exist, use default values
		err = nil
	}
	return err
}

func readConfig(cfg *Config, name string) error {
	name = filepath.Clean(name)
	f, err := os.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	return parseConfig(cfg, f)
}

func parseConfig(cfg *Config, r io.Reader) error {
	i, err := ini.Load(r)
	if err != nil {
		return err
	}
	return i.StrictMapTo(cfg)
}

func readEnv(cfg *Config) error {
	var err error
	envString(&cfg.SocketPath, "FSID_SOCKET")
	envString(&cfg.Database.TableName, "FSID_TABLE_NAME")
	envString(&cfg.Database.Region, "FSID_REGION")
	envString(&cfg.Database.Endpoint, "FSID_ENDPOINT")
	err = multierr.Append(err, envBool(&cfg.Debug, "FSID_DEBUG"))
	err = multierr.Append(err, envBool(&cfg.Cache, "FSID_CACHE"))
	return err
}

func envString(value *string, key string) {
	if s, _ := os.LookupEnv(key); s != "" {
		*value = s
	}
}

func envBool(value *bool, key string) error {
	if s, _ := os.LookupEnv(key); s != "" {
		b, err := strconv.ParseBool(s)
		if err != nil {
			return fmt.Errorf("invalid argument %q for %q: %w", s, key, err)
		}
		*value = b
	}
	return nil
}

func required(name, value string) error {
	if value == "" {
		return fmt.Errorf("required: %q", name)
	} else {
		return nil
	}
}

func printConfigError(err error) {
	msg := &strings.Builder{}
	fmt.Fprintln(msg, "invalid configuration")
	for _, e := range multierr.Errors(err) {
		fmt.Fprintf(msg, "  - %v\n", e)
	}
	log.Error.Print(msg.String())
}
