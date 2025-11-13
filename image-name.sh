#!/usr/bin/env bash

# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# extract the name of the AWS AMI(s) that were built by Packer
# supports both amd64 and arm64 architectures
exec jq -r '.builds[] |
	select((.name == "nfs-proxy-amd64" or .name == "nfs-proxy-arm64") and .builder_type == "amazon-ebs") |
	(.name | sub("nfs-proxy-"; "")) + ":" + (.artifact_id | split(":")[1])' image.manifest.json
