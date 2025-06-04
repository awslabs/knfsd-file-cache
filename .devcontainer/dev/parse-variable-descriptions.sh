#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## Summary: Terraform does not support querying of variables.tf descriptions.
## Parse the locals.descriptions{} block in "parameters.tf" for KEYs
## and extract the matched "description=" for each KEY in "variables.tf",
## then print to stdout the format "KEY = \"DESCRIPTION\"". Respects #comments
## and empty lines. Copy/Paste result into "parameters.tf" to update the
## locals.descriptions{} block.

## Usage: ./parse-variable-descriptions.sh

# Paths to the files
PARAMETERS_FILE="../../deployment/terraform-module-knfsd/parameters.tf"
VARIABLES_FILE="../../deployment/terraform-module-knfsd/variables.tf"

# Check if files exist
if [[ ! -f $PARAMETERS_FILE ]]; then
	echo "ERROR: PARAMETERS_FILE not found at: $PARAMETERS_FILE"
	exit 1
fi

if [[ ! -f $VARIABLES_FILE ]]; then
	echo "ERROR: VARIABLES_FILE not found at: $VARIABLES_FILE"
	exit 1
fi

# Extract keys and preserve empty lines and comments from the descriptions block in parameters.tf
keys_and_comments=$(awk '
	BEGIN { in_descriptions = 0; }
	/descriptions = {/ { in_descriptions = 1; next; }
	in_descriptions && /}/ { in_descriptions = 0; }
	in_descriptions {
		if (/^[[:space:]]*#|^$/) {  # Match lines with leading whitespace before #
			print $0;  # Print comments and empty lines as they are
		} else if (/=/) {
			sub(/ *=.*/, ""); print $1;
		}
	}
' "$PARAMETERS_FILE")

# Extract descriptions from variables.tf
function extract_descriptions() {
	local key="$1"
	awk -v key="$key" '
	BEGIN { in_variable = 0; var_name = ""; description = ""; }
	/variable[[:space:]]*"/ {
		in_variable = 1;
		sub(/.*variable[[:space:]]*"/, "");
		sub(/".*/, "");
		var_name = $0;
	}
	in_variable && /{/ { in_variable = 1; }
	in_variable && /}/ {
		in_variable = 0;
		if (var_name == key && description != "") {
			print "    " var_name " = \"" description "\"";
		}
	}
	in_variable && /description *=/ {
		sub(/.*description *= */, "");
		gsub(/^"|"$/, "", $0);
		description = $0;
	}
	' "$VARIABLES_FILE"
}

# Extract and print the descriptions
echo "  descriptions = {"
while IFS= read -r line; do
	# Check if the line is a comment or empty
	if [[ $line =~ ^[[:space:]]*# || -z $line ]]; then
		echo "$line" # Print comments and empty lines as they are
	else
		# Extract and print the description for the key
		extract_descriptions "$line"
	fi
done <<< "$keys_and_comments"
echo "  }"
