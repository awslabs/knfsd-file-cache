# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# https://gallery.ecr.aws/docker/library/python
# must match the Lambda function runtime
ARG KNFSD_PYTHON_VERSION=3.14.6

# nosemgrep: dockerfile-source-not-pinned
FROM public.ecr.aws/docker/library/python:${KNFSD_PYTHON_VERSION}-alpine

ARG VERSION="1.1.0-alpha.28"

LABEL org.opencontainers.image.source="https://github.com/awslabs/knfsd-file-cache"
LABEL org.opencontainers.image.description="knfsd-file-cache lambda-db-setup container image"
LABEL org.opencontainers.image.authors="knfsd-file-cache@amazon.com"
LABEL org.opencontainers.image.vendor="Amazon Web Services"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.version=${VERSION}

HEALTHCHECK NONE

RUN apk update && apk add --no-cache zip bash
