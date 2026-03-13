# Copyright 2023 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

FROM gcr.io/cloud-builders/gcloud

LABEL org.opencontainers.image.source="https://github.com/awslabs/knfsd-file-cache"
LABEL org.opencontainers.image.description="knfsd-file-cache terratest container image"
LABEL org.opencontainers.image.authors="knfsd-file-cache@amazon.com"
LABEL org.opencontainers.image.vendor="Amazon Web Services"
LABEL org.opencontainers.image.licenses="Apache-2.0"

HEALTHCHECK NONE

# the build requires the following tools:
#  - aws cli v2
#  - go v1.26.1
#  - terraform 1.2.9

# install golang (and unzip which we need later for terraform)
RUN apt-get update \
    && apt-get install -y \
    golang-1.26 \
    unzip \
    && apt-get clean \
    && rm -rf "/var/lib/apt/lists/*"

# add go to the path
ENV PATH="$PATH:/usr/lib/go-1.26/bin"

# install terraform
RUN set -eux \
    && curl -fsSL https://releases.hashicorp.com/terraform/1.2.9/terraform_1.2.9_linux_amd64.zip \
    && --output terraform.zip && unzip -q -o terraform.zip -d /usr/local/bin && rm terraform.zip
