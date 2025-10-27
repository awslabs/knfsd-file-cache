# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# https://github.com/bats-core/bats-core/releases
# https://hub.docker.com/r/bats/bats/tags
# nosemgrep: dockerfile-source-not-pinned
FROM bats/bats:1.12.0

ARG VERSION="1.1.0-alpha.12"

LABEL org.opencontainers.image.source="https://github.com/awslabs/knfsd-file-cache"
LABEL org.opencontainers.image.description="knfsd-file-cache bats test container image"
LABEL org.opencontainers.image.authors="knfsd-file-cache@amazon.com"
LABEL org.opencontainers.image.vendor="Amazon Web Services"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.version=${VERSION}

HEALTHCHECK NONE

RUN apk update && apk add --no-cache nfs-utils
