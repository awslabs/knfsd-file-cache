#!/usr/bin/env bash

# Copyright 2022 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Bind the container port 8000 to a random local port to
# avoid conflicting with any existing DynamoDB Local instances.
compose_opts=(-f dynamodb.compose.yaml)

# dummy env vars for the tests
export AWS_ACCESS_KEY_ID="fsid"
export AWS_SECRET_ACCESS_KEY="fsid"
export AWS_REGION="us-east-1"

function compose() {
	docker compose "${compose_opts[@]}" "$@"
}

function start_dynamodb() {
	compose up --wait
}

function stop_dynamodb() {
	compose down --volumes
}

function endpoint() {
	local port
	port="$(compose port dynamodb 8000)"
	# docker compose port outputs in the format ip:port, separate out the port
	port="${port##*:}"
	printf 'http://127.0.0.1:%d' "$port"
}

function run_tests() {
	TEST_DYNAMODB_ENDPOINT="$(endpoint)"
	export TEST_DYNAMODB_ENDPOINT
	go test -tags=test.dynamodb -race -cover -vet=all -v "$@" ./...
}

function cleanup() {
	if ! stop_dynamodb; then
		printf 'ERROR: Failed to stop DynamoDB Local, container might still be running\n'
		exit 1
	fi
}

case "$1" in
	# By default automatically start DynamoDB Local, run the tests then stop DynamoDB Local.
	# Shortcut for:
	#   ./test.sh up && ./test.sh run; ./test.sh down
	"")
		trap cleanup EXIT
		if ! start_dynamodb; then
			printf 'ERROR: Failed to start DynamoDB Local\n'
			exit 1
		fi

		run_tests
		;;

	up) start_dynamodb ;;

	down) stop_dynamodb ;;

	# ./test.sh up
	# ./test.sh run -run TestAllocateFSID/Race -count=50
	# ./test.sh down
	run)
		shift
		run_tests "$@"
		;;

	# print the DynamoDB Local endpoint for use with debugging in vscode
	# in .vscode/settings.json add:
	#   "go.testTags": "test.dynamodb",
	#   "go.testEnvVars": {
	#     "TEST_DYNAMODB_ENDPOINT": "<paste endpoint here>",
	#     "AWS_ACCESS_KEY_ID": "fsid",
	#     "AWS_SECRET_ACCESS_KEY": "fsid",
	#     "AWS_REGION": "us-east-1"
	#   }
	url) endpoint && printf '\n' ;;

	*) printf 'Unknown command "%s"\n' "$1" ;;
esac
