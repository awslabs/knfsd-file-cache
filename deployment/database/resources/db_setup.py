#!/usr/bin/env python

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""
This py script provides functionality for setting up a PostgreSQL database user,
IAM authentication, schema, and permissions using AWS Secrets Manager.

The AWS Lambda function retrieves database credentials and executes
necessary SQL commands to configure database access.
"""

import os
import json
import logging
import psycopg
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

# configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def get_secret(db_secret_endpoint, db_secret_region, db_secret_name):
    """
    Retrieve database credentials from AWS Secrets Manager
    """
    session = boto3.session.Session()
    script_id = "knfsd-file-cache/db-setup"
    sol_id = os.environ.get("USER_AGENT")
    combined_user_agent = f"{script_id} {sol_id}".strip()
    user_agent_extra = {"user_agent_extra": combined_user_agent}
    config = Config(**user_agent_extra)
    client = session.client(
        "secretsmanager",
        region_name=db_secret_region,
        endpoint_url=f"https://{db_secret_endpoint}",
        config=config,
    )

    logger.info("Retrieving secret")
    try:
        get_secret_value_response = client.get_secret_value(SecretId=db_secret_name)
        logger.info("Secret retrieved successfully")
    except ClientError:
        logger.warning("Failed to retrieve secret")
        raise

    return get_secret_value_response["SecretString"]


# pylint: disable=unused-argument,too-many-locals
def lambda_handler(event, context):
    """
    Lambda function to set up postgreSQL database user, iam_auth, schema and permissions
    """
    # retrieve configuration from environment variables
    db_address = os.environ.get("DB_ADDRESS")
    db_port = os.environ.get("DB_PORT")
    db_user = os.environ.get("DB_USER")
    db_name = os.environ.get("DB_NAME")
    db_secret_endpoint = os.environ.get("DB_SECRET_ENDPOINT")
    db_secret_region = os.environ.get("DB_SECRET_REGION")
    db_secret_name = os.environ.get("DB_SECRET_NAME")

    try:
        # retrieve database credentials from Secrets Manager
        db_secret_dict = json.loads(
            get_secret(db_secret_endpoint, db_secret_region, db_secret_name)
        )
        db_master_user = db_secret_dict["username"]
        db_password = db_secret_dict["password"]

        # establish database connection
        with psycopg.connect(
            host=db_address,
            port=db_port,
            dbname=db_name,
            user=db_master_user,
            password=db_password,
            autocommit=True,
        ) as conn:  # use context manager to ensure proper connection handling

            # execute SQL commands
            sql_commands = [
                f"CREATE USER {db_user};",
                f"GRANT rds_iam TO {db_user};",
                f"GRANT CONNECT ON DATABASE {db_name} TO {db_user};",
                f"GRANT USAGE, CREATE ON SCHEMA public TO {db_user};",
                # pylint: disable=line-too-long
                f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO {db_user};",
            ]

            for command in sql_commands:
                try:
                    conn.execute(command)
                    logger.info("Successfully executed: %s", command)
                except psycopg.Error as sql_err:
                    logger.error("Error executing: %s : %s", command, sql_err)
                    return {
                        "statusCode": 500,
                        "body": json.dumps(f"Error: {str(sql_err)}"),
                    }

        logger.info("Database setup completed successfully")
        return {
            "statusCode": 200,
            "body": json.dumps(
                f"Database setup completed successfully for: {db_address}"
            ),
        }

    # pylint: disable=broad-exception-caught
    except Exception as e:
        logger.error("Error in database setup: %s", str(e))
        return {"statusCode": 500, "body": json.dumps(f"Error: {str(e)}")}
