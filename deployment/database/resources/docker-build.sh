#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Build the "db_setup.zip" file for the Lambda function
# Usage: ./resources/docker-build.sh via ../main.tf

# always use x86_64 only for the DB setup image
ARCH="linux/amd64"
PIP_PLATFORM="manylinux2014_x86_64"
KNFSD_PYTHON_VERSION="3.14.4" # must match the MAJOR.MINOR version of the AWS Lambda runtime
KNFSD_PSYCOPG_VERSION="3.3.4" # https://pypi.org/project/psycopg/

# ensure resources directory is writable by all users
chmod 0777 resources

# create a hash of the Dockerfile
function create_hash() {
	if command -v sha1sum > /dev/null 2>&1; then
		sha1sum "$1" | cut -d ' ' -f 1
	elif command -v shasum > /dev/null 2>&1; then
		shasum -a 1 "$1" | cut -d ' ' -f 1
	else
		return 1
	fi
}

if ! HASH="$(create_hash resources/Dockerfile)"; then
	echo "ERROR: could not create hash for resources/Dockerfile (missing sha1sum/shasum or file not found)" >&2
	exit 1
fi

DB_SETUP_IMAGE=lambda-db-setup:"${HASH}"

# check if the image exists
if ! docker image inspect "${DB_SETUP_IMAGE}" > /dev/null 2> /dev/null; then
	if ! docker buildx build \
		--platform "${ARCH}" \
		--load \
		-t "${DB_SETUP_IMAGE}" \
		--build-arg KNFSD_PYTHON_VERSION="${KNFSD_PYTHON_VERSION}" \
		resources; then
		echo "ERROR: could not build docker image" >&2
		exit 1
	fi
fi

path="$(pwd)"
# if running in devcontainer, prefix the host repo path
if [[ $CI == "devcontainer" ]]; then
	root=$(dirname "${HOST_REPO_PATH}")
	path=${root}${path}
fi

# run the docker image
# https://www.psycopg.org/psycopg3/docs/api/pq.html#pq-impl
docker run --platform "${ARCH}" --rm \
	--volume lambda-db-setup-temp-vol:/src \
	--mount type=bind,source="${path}",target=/db "${DB_SETUP_IMAGE}" \
	bash -c "
		rm -f /db/resources/db_setup.zip
		export PIP_ROOT_USER_ACTION=ignore
		pip install --upgrade pip
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
