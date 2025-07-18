/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"math/rand" // nosemgrep
	"strings"
	"text/template" // nosemgrep
	"time"

	mw "github.com/aws/aws-sdk-go-v2/aws/middleware"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/ec2/imds"
	"github.com/aws/aws-sdk-go-v2/feature/rds/auth"
	"github.com/aws/smithy-go/middleware"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/internal/metrics"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-fsidd/log"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// The main purpose of this code is to provide a way to manage file system IDs in a database,
// allowing for the association of paths with unique identifiers (FSIDs) and vice versa.

//go:embed schema.sql
var tableSchema string

// DBWrapper struct implements the DB interface, which defines methods like BeginTx, Exec,
// QueryRow, and Close.
type DB interface {
	BeginTx(ctx context.Context, txOptions pgx.TxOptions) (pgx.Tx, error)
	Exec(ctx context.Context, sql string, arguments ...interface{}) (pgconn.CommandTag, error)
	QueryRow(ctx context.Context, sql string, args ...interface{}) pgx.Row
	Close()
}

// The DBWrapper struct wraps the database connection and provides methods for executing
// SQL queries and transactions.
type DBWrapper struct {
	db DB
}

func (w *DBWrapper) Close() {
	if w.db != nil {
		w.db.Close()
	}
}

func (w *DBWrapper) BeginTx(ctx context.Context, txOptions pgx.TxOptions) (pgx.Tx, error) {
	return w.db.BeginTx(ctx, txOptions)
}

func (w *DBWrapper) Exec(ctx context.Context, sql string, arguments ...interface{}) (pgconn.CommandTag, error) {
	return w.db.Exec(ctx, sql, arguments...)
}

func (w *DBWrapper) QueryRow(ctx context.Context, sql string, args ...interface{}) pgx.Row {
	return w.db.QueryRow(ctx, sql, args...)
}

func getRegion(ctx context.Context) (string, error) {
	// Create a default AWS configuration
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return "", err
	}

	// Create an IMDS client, disable default 5s timeout
	client := imds.NewFromConfig(cfg, func(options *imds.Options) {
		options.DisableDefaultTimeout = true
	})

	// Create new context from previous ctx with a custom 2s timeout
	// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/retries-timeouts/#timeouts
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	// Fetch the AWS region
	response, err := client.GetRegion(ctx, &imds.GetRegionInput{})
	if err != nil {
		return "", err
	}

	return response.Region, nil
}

func connect(ctx context.Context, config DatabaseConfig) (DB, error) {
	pgConfig, err := pgxpool.ParseConfig(config.URL)
	if err != nil {
		log.Error.Print("failed to parse connString config.URL")
		return nil, err
	}

	log.Debug.Printf("url: %v", pgConfig.ConnString())
	log.Debug.Printf("host: %v", pgConfig.ConnConfig.Host)
	log.Debug.Printf("port: %v", pgConfig.ConnConfig.Port)
	log.Debug.Printf("user: %v", pgConfig.ConnConfig.User)
	log.Debug.Printf("dbname: %v", pgConfig.ConnConfig.Database)
	log.Debug.Printf("iam-auth: %v", config.IAMAuth)
	log.Debug.Printf("table-name: %v", config.TableName)
	log.Debug.Printf("create-table: %v", config.CreateTable)

	if config.IAMAuth {
		// set random connection lifetime between 10-14 minutes to prevent connection storms
		randomMinutes := 10 + rand.Intn(5) // #nosec G404
		pgConfig.MaxConnLifetime = time.Duration(randomMinutes) * time.Minute
		log.Debug.Printf("max-conn-lifetime: %v", pgConfig.MaxConnLifetime)

		// get AWS region from IMDS
		region, err := getRegion(ctx)
		if err != nil {
			log.Error.Print("unable to retrieve the AWS region from the EC2 instance")
			return nil, err
		}
		log.Debug.Printf("region: %v", region)

		// create AWS config with explicit AWS region and custom user agent
		cfg, err := awsconfig.LoadDefaultConfig(ctx,
			awsconfig.WithRegion(region),
			awsconfig.WithAPIOptions([]func(*middleware.Stack) error{
				mw.AddUserAgentKeyValue("knfsd-file-cache/fsidd", version),
				mw.AddUserAgentKeyValue("AWSSOLUTION/SO9129", version),
			}),
		)
		if err != nil {
			log.Error.Print("failed to load AWS configuration")
			return nil, err
		}

		// use BeforeConnect hook to generate fresh IAM token for each connection
		pgConfig.BeforeConnect = func(ctx context.Context, connConfig *pgx.ConnConfig) error {
			log.Debug.Print("generating fresh IAM token for new connection")

			endpoint := fmt.Sprintf("%s:%d", connConfig.Host, connConfig.Port)
			// https://aws.github.io/aws-sdk-go-v2/docs/sdk-utilities/rds/
			authToken, err := auth.BuildAuthToken(
				ctx,
				endpoint,
				region,
				connConfig.User,
				cfg.Credentials,
			)
			if err != nil {
				log.Error.Print("failed to create authentication token")
				return err
			}
			log.Debug.Printf("auth token: %v", authToken)

			// set password to auth token
			connConfig.Password = authToken
			return nil
		}
	}

	log.Debug.Print("creating pgxpool")
	db, err := pgxpool.NewWithConfig(ctx, pgConfig)
	if err != nil {
		return nil, err
	}

	return &DBWrapper{db}, nil
}

// The FSIDSource struct is responsible for managing file system IDs (FSIDs) in the database.
// It provides methods for creating the database table (CreateTable), getting an FSID for a
// given path (GetFSID), allocating a new FSID for a path (AllocateFSID), and getting the path
// for a given FSID (GetPath).
type FSIDSource struct {
	db        DB
	tableName string
}

func (s FSIDSource) CreateTable(ctx context.Context) error {
	log.Debug.Printf("creating table: \"%s\"", s.tableName)

	t, err := template.New("schema").Parse(tableSchema)
	if err != nil {
		return err
	}

	w := &strings.Builder{}
	err = t.Execute(w, s.tableName)
	if err != nil {
		return err
	}

	sql := w.String()
	return withRetry(ctx, func() error {
		_, err = s.db.Exec(ctx, sql)
		return err
	})
}

func (s FSIDSource) GetFSID(ctx context.Context, path string) (int32, error) {
	var fsid int32
	start := time.Now()
	sql := fmt.Sprintf("SELECT fsid FROM \"%s\" WHERE path = $1", s.tableName)
	row := s.db.QueryRow(ctx, sql, path)
	err := row.Scan(&fsid)
	metrics.SQLOperation(ctx, "get_fsid", SQLMetricResult(err), time.Since(start))
	return fsid, err
}

func (s FSIDSource) AllocateFSID(ctx context.Context, path string) (int32, error) {
	var fsid int32
	start := time.Now()
	sql := fmt.Sprintf("INSERT INTO \"%s\" (path) VALUES ($1) RETURNING fsid", s.tableName)
	row := s.db.QueryRow(ctx, sql, path)
	err := row.Scan(&fsid)
	metrics.SQLOperation(ctx, "allocate_fsid", SQLMetricResult(err), time.Since(start))
	return fsid, err
}

func (s FSIDSource) GetPath(ctx context.Context, fsid int32) (string, error) {
	var path string
	start := time.Now()
	sql := fmt.Sprintf("SELECT path FROM \"%s\" WHERE fsid = $1", s.tableName)
	row := s.db.QueryRow(ctx, sql, fsid)
	err := row.Scan(&path)
	metrics.SQLOperation(ctx, "get_path", SQLMetricResult(err), time.Since(start))
	return path, err
}

// IsConflict and IsNotFound are helper functions that check for specific PostgreSQL
// error conditions ("unique constraint violation" and "no rows found", respectively).
func IsConflict(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		// unique constraint violation
		return pgErr.Code == "23505"
	} else {
		return false
	}
}

func IsNotFound(err error) bool {
	return errors.Is(err, pgx.ErrNoRows)
}

// SQLMetricResult is a function that returns a string representation of the SQL
// operation result (e.g., "ok", "not_found", "conflict", or "error") for metric purposes.
func SQLMetricResult(err error) string {
	switch {
	case err == nil:
		return "ok"
	case IsNotFound(err):
		return "not_found"
	case IsConflict(err):
		return "conflict"
	default:
		return "error"
	}
}
