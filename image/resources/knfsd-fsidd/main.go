/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/internal/metrics"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/log"
	"github.com/coreos/go-systemd/v22/daemon"
	"github.com/spf13/pflag"
)

var version = "dev"

type FSIDProvider interface {
	GetFSID(ctx context.Context, path string) (int32, error)
	AllocateFSID(ctx context.Context, path string) (int32, error)
	GetPath(ctx context.Context, fsid int32) (string, error)
}

func main() {
	var err error
	var showVersion bool

	cfg := new(Config)
	f := pflag.NewFlagSet(os.Args[0], pflag.ContinueOnError)

	// setup flags before reading the config files, otherwise the pflag package
	// will overwrite the config with the default values
	f.StringVar(&cfg.SocketPath, "socket", defaultSocketPath, "The unix socket to listen on for incoming FSID requests from 'mountd'. This *must* match the value configured in '/etc/nfs.conf'")
	f.StringVar(&cfg.Database.TableName, "table-name", "", "The name of the Amazon DynamoDB table storing the FSID mappings for the proxy cluster. Authentication is handled by the AWS GO v2 SDK using the IAM instance profile")
	f.StringVar(&cfg.Database.Region, "region", "", "The AWS region hosting the DynamoDB table. When empty the region is resolved from the environment, falling back to the EC2 instance metadata service (IMDSv2)")
	f.StringVar(&cfg.Database.Endpoint, "endpoint", "", "Overrides the DynamoDB service endpoint URL. Only intended for testing against DynamoDB Local")
	f.BoolVar(&cfg.Cache, "cache", true, "Enables caching FSID mappings to avoid querying FSID database. Setting this to false can result in excessive DynamoDB queries and slow performance and is only intended for debugging")
	f.BoolVar(&cfg.Debug, "debug", false, "Enabled writing verbose debug output to 'stderr'")
	f.BoolVarP(&showVersion, "version", "v", false, "Show version and exit")
	f.SortFlags = false

	// read the config file before parsing the command line arguments so
	// that the command line arguments override any config values
	err = readDefaultConfig(cfg)
	if err != nil {
		log.Error.Printf("could not read config: %s", err)
		os.Exit(2)
	}

	// override values from the config file with environment variables
	err = readEnv(cfg)
	if err != nil {
		printConfigError(err)
		os.Exit(2)
	}

	// command line arguments overrides all other sources
	err = f.Parse(os.Args[1:])
	if errors.Is(err, pflag.ErrHelp) {
		os.Exit(0)
	}
	if err != nil {
		log.Error.Print(err)
		os.Exit(2)
	}

	if showVersion {
		fmt.Println(version)
		os.Exit(0)
	}

	if cfg.Debug {
		log.EnableDebug()
	}

	err = cfg.Validate()
	if err != nil {
		printConfigError(err)
		os.Exit(2)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	if err = run(ctx, cfg); err != nil {
		log.Error.Print(err)
		cancel()
		os.Exit(1) // nolint:gocritic // Context cancellation handled explicitly before os.Exit(1)
	}
}

func run(ctx context.Context, cfg *Config) error {
	var err error

	m := metrics.Start(ctx, cfg.Metrics)
	defer func() {
		deadline, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		err := m.Shutdown(deadline)
		if err != nil {
			log.Warn.Printf("metrics did not shutdown gracefully: %s", err)
		}
	}()

	client, err := connect(ctx, cfg.Database)
	if err != nil {
		return err
	}

	source := FSIDSource{
		client:    client,
		tableName: cfg.Database.TableName,
	}

	// The table itself is provisioned by Terraform (deployment/database);
	// verify it is reachable before accepting requests from mountd.
	err = source.CheckTable(ctx)
	if err != nil {
		return err
	}

	var f FSIDProvider
	if cfg.Cache {
		f = &FSIDCache{source: source}
	} else {
		f = source
	}

	s, err := resolveSocket(cfg.SocketPath)
	if err != nil {
		return err
	}
	defer s.Close()

	s.Handle("get_fsidnum", func(ctx context.Context, path string) (string, error) {
		rec := metrics.StartRequest("get_fsidnum")
		if path == "" {
			rec.End(ctx, "error")
			return "", ErrInvalidArgument
		}

		var fsid int32
		err := withRetry(ctx, func() error {
			var err error
			rec := rec.StartOperation()
			fsid, err = f.GetFSID(ctx, path)
			rec.End(ctx, DBMetricResult(err))
			return err
		})

		rec.End(ctx, DBMetricResult(err))

		switch {
		case err == nil:
			return strconv.FormatInt(int64(fsid), 10), nil
		case IsNotFound(err):
			return "", nil
		default:
			return "", err
		}
	})

	s.Handle("get_or_create_fsidnum", func(ctx context.Context, path string) (string, error) {
		rec := metrics.StartRequest("get_or_create_fsidnum")
		if path == "" {
			rec.End(ctx, "error")
			return "", ErrInvalidArgument
		}

		var fsid int32
		err = withRetry(ctx, func() error {
			var err error
			rec := rec.StartOperation()
			fsid, err = f.GetFSID(ctx, path)
			if IsNotFound(err) {
				// FSID not found for path, so try and allocate one.
				// This might fail with ErrConflict if the path has already
				// been allocated an FSID by a different process (the
				// conditional write on the PATH# item fails). withRetry will
				// then retry this whole block and will find the FSID
				// allocated by the other process.
				fsid, err = f.AllocateFSID(ctx, path)
			}
			rec.End(ctx, DBMetricResult(err))
			return err
		})

		rec.End(ctx, DBMetricResult(err))
		return strconv.FormatInt(int64(fsid), 10), err
	})

	s.Handle("get_path", func(ctx context.Context, arg string) (string, error) {
		rec := metrics.StartRequest("get_path")
		fsid, err := strconv.ParseInt(arg, 10, 32)
		if err != nil {
			rec.End(ctx, "error")
			return "", ErrInvalidArgument
		}
		if fsid < 1 {
			rec.End(ctx, "error")
			return "", ErrInvalidArgument
		}

		var path string
		err = withRetry(ctx, func() error {
			var err error
			rec := rec.StartOperation()
			path, err = f.GetPath(ctx, int32(fsid)) // #nosec G115
			rec.End(ctx, DBMetricResult(err))
			return err
		})

		rec.End(ctx, DBMetricResult(err))
		return path, err
	})

	s.Handle("version", func(ctx context.Context, arg string) (string, error) {
		metrics.Request(ctx, "version", "ok", 0, 0)
		return "1", nil
	})

	go func() {
		<-ctx.Done()
		_, err := daemon.SdNotify(false, daemon.SdNotifyStopping)
		if err != nil {
			log.Error.Print(err)
		}

		deadline, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()

		err = s.Shutdown(deadline)
		if err != nil {
			log.Error.Print(err)
		}
		if closeErr := s.Close(); closeErr != nil {
			log.Error.Printf("error closing socket: %v", closeErr)
		}
	}()

	_, err = daemon.SdNotify(false, daemon.SdNotifyReady)
	if err != nil {
		return err
	}
	log.Info.Print("service ready")

	err = s.Serve()
	if errors.Is(err, ErrServerClosed) {
		err = nil
	}
	return err
}
