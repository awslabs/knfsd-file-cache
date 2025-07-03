/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# Validate that the proxy AMI exists and is accessible.
# "Error: Your query returned no results. Please change your search criteria and try again."
# tflint-ignore: terraform_unused_declarations
data "aws_ami" "proxy" {
  filter {
    name   = "image-id"
    values = [var.PROXY_AMI]
  }
}

# To maintain Tf v1.2 support, we need to use null_resource to validate cross-referencing variables.
resource "null_resource" "validations" {
  lifecycle {
    precondition {
      condition     = var.HEALTHCHECK_TIMEOUT_SECONDS <= var.HEALTHCHECK_INTERVAL_SECONDS
      error_message = "HEALTHCHECK_TIMEOUT_SECONDS (${var.HEALTHCHECK_TIMEOUT_SECONDS}) must be less than or equal to HEALTHCHECK_INTERVAL_SECONDS (${var.HEALTHCHECK_INTERVAL_SECONDS})."
    }
    precondition {
      condition     = var.CACHEFILESD_DISK_TYPE != "ebs-gp3" || (var.CACHEFILESD_EBS_SIZE >= 1 && var.CACHEFILESD_EBS_SIZE <= 16384)
      error_message = "For ebs-gp3, CACHEFILESD_EBS_SIZE must be between 1 and 16384 GiB."
    }
    precondition {
      condition     = var.CACHEFILESD_DISK_TYPE != "ebs-io2" || (var.CACHEFILESD_EBS_SIZE >= 4 && var.CACHEFILESD_EBS_SIZE <= 65536)
      error_message = "For ebs-io2, CACHEFILESD_EBS_SIZE must be between 4 and 65536 GiB."
    }
    precondition {
      condition     = var.CACHEFILESD_DISK_TYPE != "ebs-gp3" || (var.CACHEFILESD_EBS_IOPS >= 3000 && var.CACHEFILESD_EBS_IOPS <= 16000)
      error_message = "For ebs-gp3, CACHEFILESD_EBS_IOPS must be between 3000 and 16000."
    }
    precondition {
      condition     = var.CACHEFILESD_DISK_TYPE != "ebs-io2" || (var.CACHEFILESD_EBS_IOPS >= 100 && var.CACHEFILESD_EBS_IOPS <= 256000)
      error_message = "For ebs-io2, CACHEFILESD_EBS_IOPS must be between 100 and 256000."
    }
    precondition {
      condition     = var.CACHEFILESD_DISK_TYPE != "ebs-gp3" || (var.CACHEFILESD_EBS_THROUGHPUT >= 125 && var.CACHEFILESD_EBS_THROUGHPUT <= 1000)
      error_message = "For ebs-gp3, CACHEFILESD_EBS_THROUGHPUT must be between 125 and 1000 MiB/s."
    }
    precondition {
      condition     = var.ENABLE_NETAPP_AUTO_DETECT || var.EXPORT_MAP != "" || var.EXPORT_HOST_AUTO_DETECT != ""
      error_message = "At least one of EXPORT_MAP, EXPORT_HOST_AUTO_DETECT must be non-empty or ENABLE_NETAPP_AUTO_DETECT must be true."
    }
    precondition {
      condition     = !var.ENABLE_NETAPP_AUTO_DETECT || var.NETAPP_HOST != ""
      error_message = "NETAPP_HOST must not be empty when ENABLE_NETAPP_AUTO_DETECT is true."
    }
    precondition {
      condition     = !var.ENABLE_NETAPP_AUTO_DETECT || var.NETAPP_URL != ""
      error_message = "NETAPP_URL must not be empty when ENABLE_NETAPP_AUTO_DETECT is true."
    }
    precondition {
      condition     = !var.ENABLE_NETAPP_AUTO_DETECT || var.NETAPP_USER != ""
      error_message = "NETAPP_USER must not be empty when ENABLE_NETAPP_AUTO_DETECT is true."
    }
    precondition {
      condition     = !var.ENABLE_NETAPP_AUTO_DETECT || var.NETAPP_SECRET != ""
      error_message = "NETAPP_SECRET must not be empty when ENABLE_NETAPP_AUTO_DETECT is true."
    }
    precondition {
      condition     = !var.ENABLE_NETAPP_AUTO_DETECT || var.NETAPP_SECRET_VERSION != ""
      error_message = "NETAPP_SECRET_VERSION must not be empty when ENABLE_NETAPP_AUTO_DETECT is true."
    }
    precondition {
      condition     = !var.ENABLE_NETAPP_AUTO_DETECT || var.NETAPP_CA != ""
      error_message = "NETAPP_CA must not be empty when ENABLE_NETAPP_AUTO_DETECT is true."
    }

    # Most of these preconditions are conditional. Terraform 1.20 does not have
    # support for some kind of "enabled" or "when" condition, so write the
    # conditions in the form:
    #   condition = (when ? check : true)
    #
    # This roughly translates to
    #   if when then
    #     check precondition
    #   else
    #     skip precondition

    precondition {
      # AUTO_REEXPORT requires an fsid service to be enabled
      condition = (
        var.AUTO_REEXPORT
        ? contains(["local", "external"], var.FSID_MODE)
        : true
      )
      error_message = "FSID_MODE must be either \"local\" or \"external\" when AUTO_REEXPORT is enabled."
    }

    # If this module has created the database ensure that the user did not try
    # and provide their own FSID_DATABASE_CONFIG, as that configuration will be
    # ignored.
    # This just avoids two possible errors:
    #   * This module ignores the custom configuration leading to confusion.
    #   * This module uses the custom configuration leading to an unused RDS
    #     PostgreSQL database being deployed.
    precondition {
      condition = (
        var.FSID_MODE == "external" && var.FSID_DATABASE_DEPLOY
        ? length(var.FSID_DATABASE_CONFIG) == 0
        : true
      )
      error_message = "You can only provide a custom FSID_DATABASE_CONFIG when using a custom external fsid database (FSID_MODE = \"external\" and FSID_DATABASE_DEPLOY = false)."
    }

    # Again to avoid confusion, if not using an external database do not allow
    # the user to provide their own FSID_DATABASE_CONFIG.
    precondition {
      condition = (
        var.FSID_MODE != "external"
        ? length(var.FSID_DATABASE_CONFIG) == 0
        : true
      )
      error_message = "You can only provide a custom FSID_DATABASE_CONFIG when using a custom external fsid database (FSID_MODE = \"external\" and FSID_DATABASE_DEPLOY = false)."
    }

    # When using a custom external database then FSID_DATABASE_CONFIG must be provided
    precondition {
      condition = (
        var.FSID_MODE == "external" && !var.FSID_DATABASE_DEPLOY
        ? length(var.FSID_DATABASE_CONFIG) > 0
        : true
      )
      error_message = "You must specify a database configuration (FSID_DATABASE_CONFIG) when using a custom external database (FSID_MODE = \"external\" and FSID_DATABASE_DEPLOY = false)."
    }

    # NOTE: We don't validate FSID_DATABASE_IAM_POLICY != "" here because:
    # * In fanout deployments, this variable contains module.fsid_database[0].db_iam_policy
    # * Terraform can't evaluate computed values in preconditions during plan phase
    # * The IAM policy attachment will fail at apply time if the ARN is invalid
    # * The variable validation already ensures it's a valid ARN format when provided

    # Bug check: This should not occur and indicates a bug in the Terraform script.
    # Fail early during terraform plan, otherwise the proxy will deploy and enter
    # a reboot loop.
    precondition {
      condition = (
        local.deploy_fsid_database
        ? local.fsid_database_config != ""
        : true
      )
      error_message = "BUG: automatic database configuration not set for external fsid database."
    }

    # Bug check: This should not occur and indicates a bug in the Terraform script.
    # Check that if the script deployed a RDS PostgreSQL database, that database will
    # be used by the proxy otherwise its just wasting money.
    # Including this here as this is the likely place people will update when
    # changing how FSID_MODE is handled as this is the main proxy validation.
    # This acts as a cross check for the local.deploy_fsid_database logic in
    # case only one is updated.
    precondition {
      condition = (
        local.deploy_fsid_database
        ? var.FSID_MODE == "external"
        : true
      )
      error_message = "BUG: deployed RDS PostgreSQL database, but that database is not in use."
    }
  }
}
