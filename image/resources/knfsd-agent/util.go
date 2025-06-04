/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"os/exec"
	"strings"
)

// combineMultiline combines multiline strings into a single string
func combineMultiline(input string) string {
	if len(strings.TrimSpace(input)) == 0 {
		return ""
	}
	lines := strings.Split(input, "\n")
	output := strings.Join(lines, ",")
	return output
}

func getNFSRootDir() (string, error) {
	out, err := exec.Command("nfsconf", "--get", "exports", "rootdir").Output()
	if err != nil {
		return "", err
	}

	nfsRoot := strings.TrimSpace(string(out))
	if !strings.HasSuffix(nfsRoot, "/") {
		nfsRoot += "/"
	}
	return nfsRoot, nil
}

func isNFS(t string) bool {
	return t == "nfs" || t == "nfs4"
}
