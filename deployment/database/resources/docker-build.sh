#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Build the "db_setup.zip" file for the Lambda function
# Usage: ./resources/docker-build.sh via ../main.tf

ARCH=${1:-"linux/arm64"}
PIP_PLATFORM="manylinux2014_aarch64"
KNFSD_PYTHON_VERSION=${2:-"3.13.3"}
KNFSD_PSYCOPG_VERSION=${3:-"3.2.9"}

# create a hash of the Dockerfile
if ! HASH="$(sha1sum resources/Dockerfile | cut -d ' ' -f 1)"; then
	echo "ERROR: could not create sha1sum for resources/Dockerfile" >&2
	exit 1
fi

DB_SETUP_IMAGE=lambda-db-setup-"$HASH"

# check if the image exists
if ! docker image inspect "${DB_SETUP_IMAGE}" > /dev/null 2> /dev/null; then
	if ! docker build \
		--platform "${ARCH}" \
		-t "${DB_SETUP_IMAGE}" \
		--build-arg KNFSD_PYTHON_VERSION="${KNFSD_PYTHON_VERSION}" \
		resources; then
		echo "ERROR: could not build docker image" >&2
		exit 1
	fi
fi

path="$(pwd)"
# if running in devcontainer, use the host repo path
if [[ $CI == "devcontainer" ]]; then
	root=$(dirname "${HOST_REPO_PATH}")
	path=${root}${path}
fi

# Determine the pip platform based on the arch
if [[ $ARCH == "linux/amd64" ]]; then
	PIP_PLATFORM="manylinux2014_x86_64"
fi

# run the docker image
# https://www.psycopg.org/psycopg3/docs/api/pq.html#pq-impl
docker run --platform "${ARCH}" --name lambda-db-setup --rm \
	--volume lambda-db-setup-temp-vol:/src \
	--mount type=bind,source="${path}",target=/db "${DB_SETUP_IMAGE}" \
	bash -c "
		rm -f /db/resources/db_setup.zip
		export PIP_ROOT_USER_ACTION=ignore
		pip3 install \
			--platform ${PIP_PLATFORM} \
			--target=/src \
			--implementation cp \
			--python-version ${KNFSD_PYTHON_VERSION} \
			--only-binary=:all: \
			psycopg[binary]==${KNFSD_PSYCOPG_VERSION}
		cd /src
		find . -type d -name '__pycache__' -exec rm -rf {} +
		find . -type d -name '*.dist-info' -exec rm -rf {} +
		cp /db/resources/db_setup.py .
		zip -qr /db/resources/db_setup.zip .
	"

# remove the temp volume
docker volume rm lambda-db-setup-temp-vol > /dev/null
