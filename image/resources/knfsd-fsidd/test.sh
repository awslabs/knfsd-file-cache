#!/usr/bin/env bash

# Copyright 2022 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Bind the container port 5432 to a random local port to
# avoid conflicting with any existing PostgreSQL instances.
export POSTGRES_PORT=0
compose_opts=(-f postgres.compose.yaml)

if [[ $CI == "codebuild" ]]; then
	# When running on AWS CodeBuild bind to the standard 5432 port
	export POSTGRES_PORT=5432
	compose_opts+=(-f codebuild.compose.yaml)
fi

function compose() {
	docker compose "${compose_opts[@]}" "$@"
}

function start_postgres() {
	compose up --wait
}

function stop_postgres() {
	compose down --volumes
}

function url() {
	if [[ $CI == "codebuild" ]]; then
		# When running on AWS CodeBuild the postgres compose service is bound to
		# port 5432 on the host (see codebuild.compose.yaml) so the build
		# container can reach it via 127.0.0.1.
		printf 'host=127.0.0.1 port=5432 user=fsidd password=fsid-test dbname=fsids'
	else
		local port
		port="$(compose port postgres 5432)"
		# docker compose port outputs in the format ip:port, separate out the port
		port="${port##*:}"
		printf 'host=127.0.0.1 port=%d user=fsidd password=fsid-test dbname=fsids' "$port"
	fi
}

function run_tests() {
	TEST_DATABASE_URL="$(url)"
	export TEST_DATABASE_URL
	go test -tags=test.sql -race -cover -vet=all -v "$@" ./...
}

function cleanup() {
	if ! stop_postgres; then
		printf 'ERROR: Failed to stop postgres, container might still be running\n'
		exit 1
	fi
}

case "$1" in
	# By default automatically start postgres, run the tests then stop postgres.
	# Shortcut for:
	#   ./test.sh up && ./test.sh run; ./test.sh down
	"")
		trap cleanup EXIT
		if ! start_postgres; then
			printf 'ERROR: Failed to start postgres\n'
			exit 1
		fi

		run_tests
		;;

	up) start_postgres ;;

	down) stop_postgres ;;

	# ./test.sh up
	# ./test.sh run -run TestAllocateFSID/Race -count=50
	# ./test.sh down
	run)
		shift
		run_tests "$@"
		;;

	# print the database URL for use with debugging in vscode
	# in .vscode/settings.json add:
	#   "go.testTags": "test.sql",
	#   "go.testEnvVars": {
	#     "TEST_DATABASE_URL": "<paste url here>"
	#   }
	url) url && printf '\n' ;;

	*) printf 'Unknown command "%s"\n' "$1" ;;
esac
