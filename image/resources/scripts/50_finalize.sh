#!/usr/bin/env bash

# Copyright 2020 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -o errexit

# terminal colors
SHELL_YELLOW='\033[0;33m'
SHELL_DEFAULT='\033[0m'

# print system info
echo -e "${SHELL_YELLOW}---- SYSTEM INFO${SHELL_DEFAULT}"
lsb_release -d -r -c
echo -e "Kernel:\t${SHELL_YELLOW}$(uname -r)${SHELL_DEFAULT}"

echo -e "\n${SHELL_YELLOW}---- SUCCESS: Finished finalize image script${SHELL_DEFAULT}"
