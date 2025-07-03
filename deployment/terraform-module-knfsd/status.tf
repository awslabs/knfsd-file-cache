/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# null resource that waits for all ASG instances to be ready
resource "null_resource" "status_check" {
  count = var.ENABLE_STATUS_CHECK ? 1 : 0

  # This provisioner will automatically assume the role specified in var.ASSUME_ROLE_ARN
  # if provided, otherwise it will use the existing AWS credentials from the environment.
  # This is useful for CI/CD pipelines where you need to assume a specific role for
  # AWS CLI commands while Terraform uses a different role via the AWS provider.
  provisioner "local-exec" {
    when        = create
    working_dir = path.module
    interpreter = local.is_windows ? ["git-bash", "-c"] : ["/bin/bash", "-c"]
    command     = <<-EOF
      # Check if role assumption is required
      if [ -n "${var.ASSUME_ROLE_ARN}" ]; then
        echo "Assuming role: ${var.ASSUME_ROLE_ARN}"
        # Assume the role and get temporary credentials
        ROLE_CREDS=$(aws sts assume-role --role-arn "${var.ASSUME_ROLE_ARN}" --role-session-name "terraform-status-check" --output json)
        export AWS_ACCESS_KEY_ID=$(echo $ROLE_CREDS | jq -r '.Credentials.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(echo $ROLE_CREDS | jq -r '.Credentials.SecretAccessKey')
        export AWS_SESSION_TOKEN=$(echo $ROLE_CREDS | jq -r '.Credentials.SessionToken')
        echo "Role assumption completed successfully"
      else
        echo "No role assumption required, using existing AWS credentials"
      fi

      echo "Waiting for [${var.KNFSD_NODES}] instances in ASG [${aws_autoscaling_group.knfsd_asg.name}] to be ready..."

      # set timeout to 60 mins
      TIMEOUT_SECONDS=3600
      START_TIME=$(date +%s)

      while true; do
        # check if timeout has been reached
        CURRENT_TIME=$(date +%s)
        ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

        if [ "$ELAPSED_TIME" -ge "$TIMEOUT_SECONDS" ]; then
          echo "ERROR: Timeout reached. Status check failed."
          exit 1
        fi

        # get all status tag values and check for any that start with "error"
        STATUS_VALUES=$(aws ec2 describe-instances \
          --region ${local.region} \
          --filters "Name=tag:aws:autoscaling:groupName,Values=${aws_autoscaling_group.knfsd_asg.name}" \
                    "Name=instance-state-name,Values=running" \
          --query 'Reservations[].Instances[].Tags[?Key==`knfsd-file-cache:status`].Value' \
          --output text)

        ERROR_COUNT=0
        if [ -n "$STATUS_VALUES" ]; then
          ERROR_COUNT=$(echo "$STATUS_VALUES" | grep -ic "^error" || true)
        fi

        if [ "$ERROR_COUNT" -gt "0" ]; then
          echo "ERROR: Found [$ERROR_COUNT] instances with error status:"
          aws ec2 describe-instances \
            --region ${local.region} \
            --filters "Name=tag:aws:autoscaling:groupName,Values=${aws_autoscaling_group.knfsd_asg.name}" \
                      "Name=instance-state-name,Values=running" \
            --query 'Reservations[].Instances[?Tags[?Key==`knfsd-file-cache:status` && starts_with(Value, `error`)]].[InstanceId,Tags[?Key==`knfsd-file-cache:status`].Value|[0]]' \
            --output text | while read -r instance_id error_msg; do
              echo "  Instance: $instance_id - Status: $error_msg"
            done
          exit 1
        fi

        # check for ready instances
        READY_COUNT=$(aws ec2 describe-instances \
          --region ${local.region} \
          --filters "Name=tag:aws:autoscaling:groupName,Values=${aws_autoscaling_group.knfsd_asg.name}" \
                    "Name=tag:knfsd-file-cache:status,Values=ready" \
                    "Name=instance-state-name,Values=running" \
          --query 'length(Reservations[].Instances[])' \
          --output text)

        if [ "$READY_COUNT" -ge "${var.KNFSD_NODES}" ]; then
          echo "[${var.KNFSD_NODES}] instances are ready!"
          break
        fi

        REMAINING_TIME=$((TIMEOUT_SECONDS - ELAPSED_TIME))
        REMAINING_MINUTES=$((REMAINING_TIME / 60))
        echo "Waiting for instances to be ready [$${READY_COUNT}/${var.KNFSD_NODES}]... ($${REMAINING_MINUTES}m before timeout)"
        sleep 60
      done
    EOF
  }

  depends_on = [aws_autoscaling_group.knfsd_asg]
}
