/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"net/http"

	"github.com/acobaugh/osrelease"
	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-agent/client"
	"golang.org/x/sys/unix"
)

func handleOS(*http.Request) (*client.OSResponse, error) {
	kernel, err := kernelVersion()
	if err != nil {
		return nil, err
	}

	os, err := osrelease.Read()
	if err != nil {
		return nil, err
	}

	return &client.OSResponse{
		Kernel: kernel,
		OS:     os,
	}, nil
}

func kernelVersion() (string, error) {
	var uts unix.Utsname
	err := unix.Uname(&uts)
	if err != nil {
		return "", err
	}
	return unix.ByteSliceToString(uts.Release[:]), nil
}
