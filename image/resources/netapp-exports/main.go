/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"

	"netapp-exports/internal/opt"
)

func main() {
	var (
		config       *Config
		configFile   string
		passwordFile string
		caFile       string
		insecure     bool
		err          error
	)

	server := &NetAppServer{
		TLS: &TLSConfig{},
	}
	secret := AWSSecret{}

	flags := flag.CommandLine
	opts := opt.NewOptSet(flags)

	flags.StringVar(&configFile, "config", "", "Config *.hcl file")

	opts.StringVar(&server.Host, "host", "NETAPP_HOST", "NetApp Host")
	opts.StringVar(&server.URL, "url", "NETAPP_URL", "NetApp URL")
	opts.StringVar(&server.User, "user", "NETAPP_USER", "NetApp User")
	opts.StringVar(&server.Password, "password", "NETAPP_PASSWORD", "NetApp password")
	opts.StringVar(&passwordFile, "password-file", "NETAPP_PASSWORD_FILE", "File containing NetApp password")

	opts.StringVar(&secret.Region, "secret-region", "NETAPP_SECRET_REGION", "AWS Secrets Manager REGION containing NetApp password")
	opts.StringVar(&secret.Name, "secret-name", "NETAPP_SECRET", "AWS Secrets Manager NAME containing NetApp password")
	opts.StringVar(&secret.Version, "secret-version", "NETAPP_SECRET_VERSION", "AWS Secrets Manager VERSION containing NetApp password. Default: AWSCURRENT")

	opts.StringVar(&caFile, "ca", "NETAPP_CA", "Path to NetApp SSL root certificate in PEM format")
	flags.BoolVar(&insecure, "insecure", false, "Allow insecure TLS connections (ignore server certificate)")
	opts.BoolVar(&server.TLS.AllowCommonName, "allow-common-name", "NETAPP_ALLOW_COMMON_NAME", "Allow using the Common Name (CN) field from the certificate's subject. By default only Subject Alternate Names (SANs) are supported")

	err = opts.Parse(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %s\n", err)
		os.Exit(1)
	}

	if configFile != "" {
		config, err = parseConfigFile(configFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ERROR: Could not read config file %s: %v\n", configFile, err)
			os.Exit(1)
		}
	} else {
		if passwordFile != "" {
			password, err := readFirstLine(passwordFile)
			if err != nil {
				fmt.Fprintf(os.Stderr, "ERROR: Could not read password file %s: %v\n", passwordFile, err)
				os.Exit(1)
			}
			server.Password = password
		}

		if caFile != "" {
			caFile = filepath.Clean(caFile)
			cert, err := os.ReadFile(caFile)
			if err != nil {
				fmt.Fprintf(os.Stderr, "ERROR: Could not read CA file %s: %v\n", caFile, err)
				os.Exit(1)
			}
			server.TLS.CACertificate = string(cert)
		}

		if secret.Name != "" {
			server.SecurePassword = &NetAppPassword{
				AWSSecret: &secret,
			}
		}

		err = server.validate()
		if err != nil {
			fmt.Fprintf(os.Stderr, "ERROR: %s\n", err)
			os.Exit(1)
		}

		config = &Config{
			Servers: []*NetAppServer{server},
		}
	}

	if insecure {
		fmt.Fprint(os.Stderr, "WARNING: Using insecure TLS is vulnerable to man in the middle attacks and should only be used for testing\n")
	}

	for _, s := range config.Servers {
		s.TLS.insecure = insecure
		err = listExports(os.Stdout, s)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ERROR: Could not list exports for %s: %v\n", s.Host, err)
			os.Exit(1)
		}
	}
}

func listExports(w io.Writer, s *NetAppServer) error {
	password, err := resolvePassword(s)
	if err != nil {
		return err
	}

	transport, err := s.TLS.transport()
	if err != nil {
		return err
	}

	client := &http.Client{
		Transport: transport,
	}

	api := &API{
		Client:   client,
		BaseURL:  s.URL,
		User:     s.User,
		Password: password,
	}

	paths, err := api.FetchAll()
	if err != nil {
		return err
	}

	sort.Strings(paths)
	for _, path := range paths {
		fmt.Fprintf(w, "%s %s\n", s.Host, path)
	}
	return nil
}

func resolvePassword(s *NetAppServer) (string, error) {
	if s.Password != "" {
		return s.Password, nil
	}

	password, err := s.SecurePassword.AWSSecret.get(context.Background())
	if err != nil {
		return "", fmt.Errorf("could not fetch password from AWS Secrets Manager: %w", err)
	}
	return password, nil
}

func readFirstLine(name string) (string, error) {
	name = filepath.Clean(name)
	f, err := os.Open(name)
	if err != nil {
		return "", err
	}
	defer f.Close()

	s := bufio.NewScanner(f)
	if s.Scan() {
		return s.Text(), nil
	}

	err = s.Err()
	if err == nil {
		err = fmt.Errorf("failed to read %s", name)
	}
	return "", err
}
