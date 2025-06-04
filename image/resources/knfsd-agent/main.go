/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

var showVersion = flag.Bool("version", false, "show version and exit")
var version = "dev"

func configureLogging() {
	// Create Logging Directory if it does not exist
	err := os.MkdirAll("/var/log/knfsd-agent", 0600)
	if err != nil {
		log.Fatalf("Error creating logging directory: %s", err.Error())
	}

	// Setup Logging
	file, err := os.OpenFile("/var/log/knfsd-agent/agent.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644) // #nosec G302 // nosemgrep
	if err != nil {
		log.Fatalf("Error creating logging file: %s", err.Error())
	}
	log.SetOutput(file)
}

func main() {
	log.SetFlags(0)
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		os.Exit(0)
	}
	configureLogging()
	mux := http.NewServeMux()
	registerRoutes(mux)

	server := &http.Server{
		Addr:         ":80",
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Println("KNFSD Agent is listening on web server port 80...")
	log.Fatal(server.ListenAndServe()) // nosemgrep
}
