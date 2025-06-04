#!/usr/bin/env bash

# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# extract the name of the AWS AMI that was built by Packer
exec jq -r '.builds[] |
	select(.name == "nfs-proxy" and .builder_type == "amazon-ebs") |
	.artifact_id' image.manifest.json
