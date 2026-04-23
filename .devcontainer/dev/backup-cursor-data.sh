#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Usage: ./backup-cursor-data.sh

set -euo pipefail

DEST_DIR="/home/ubuntu"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE_PATH="${DEST_DIR}/cursor-backup-${TIMESTAMP}.tar.gz"
SOURCE_DIR="/home/ubuntu/.cursor"
SOURCE_BASENAME="$(basename "${SOURCE_DIR}")"

tar -czf "${ARCHIVE_PATH}" -C "$(dirname "${SOURCE_DIR}")" --transform="s|^${SOURCE_BASENAME}|cursor|" "${SOURCE_BASENAME}"
echo "Backup created: ${ARCHIVE_PATH}"
