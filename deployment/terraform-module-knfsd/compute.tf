/*
 * Copyright 2020 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# local variables
locals {
  ebs_vol_type = var.CACHEFILESD_DISK_TYPE == "ebs-gp3" ? "gp3" : "io2"
}

# Optionally create an EC2 Capacity Reservation for the cluster
# The KNFSD nodes are often large instances. This means they can sometimes be difficult
# to schedule which can cause delays when replacing unhealthy instances, or performing
# rolling replacements. A reservation ensures that the capacity for the KNFSD cluster
# is always available in AWS, regardless of the state of the instances. A reservation
# is not a commitment, and can be deleted at any time.
resource "aws_ec2_capacity_reservation" "knfsd_reservation" {
  count                   = var.RESERVE_KNFSD_CAPACITY ? 1 : 0
  instance_count          = var.KNFSD_NODES
  instance_type           = var.INSTANCE_TYPE
  availability_zone       = local.az
  instance_platform       = "Linux/UNIX"
  instance_match_criteria = "targeted"
  tags                    = merge(local.tags, { Name = "${local.name}-reservation" })

  lifecycle {
    precondition {
      # RESERVE_KNFSD_CAPACITY requires ENABLE_KNFSD_AUTOSCALING to be false
      condition     = var.ENABLE_KNFSD_AUTOSCALING == false
      error_message = "ENABLE_KNFSD_AUTOSCALING must be disabled when RESERVE_KNFSD_CAPACITY is enabled."
    }
  }
}

# Instance template for the KNFSD instances
resource "aws_launch_template" "nfsproxy_template" {
  name                   = "${local.name}-lt"
  description            = "EC2 instance template for the KNFSD instances"
  image_id               = var.PROXY_AMI
  instance_type          = var.INSTANCE_TYPE
  key_name               = var.KEY_NAME
  vpc_security_group_ids = [aws_security_group.nfsproxy_asg_sg.id]

  ebs_optimized = true

  # 100GB root vol
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.ROOT_DISK_SIZE
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # EBS fs-cache disk configuration (optional)
  dynamic "block_device_mappings" {
    for_each = var.CACHEFILESD_DISK_TYPE != "local-nvme" ? toset([for i in range(var.CACHEFILESD_EBS_COUNT) : tostring(i)]) : []
    content {
      device_name = format("/dev/sd%s", [for i in range(8) : ["f", "g", "h", "i", "j", "k", "l", "m"][i]][tonumber(block_device_mappings.value)])
      ebs {
        volume_type           = local.ebs_vol_type
        volume_size           = var.CACHEFILESD_EBS_SIZE
        iops                  = var.CACHEFILESD_EBS_IOPS
        throughput            = var.CACHEFILESD_EBS_THROUGHPUT
        delete_on_termination = true
        encrypted             = true
      }
    }
  }

  tags = local.tags

  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name"                    = local.name,
      "knfsd-file-cache:status" = "starting"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      "Name"                     = "${local.name}-vol",
      "knfsd-file-cache:version" = var.VERSION
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.knfsd_instance_profile.name
  }

  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    instance_metadata_tags = "enabled"
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(<<-EOT
  Content-Type: multipart/mixed; boundary="==BOUNDARY=="
  MIME-Version: 1.0

  --==BOUNDARY==
  Content-Type: text/cloud-config; charset="us-ascii"
  MIME-Version: 1.0
  Content-Transfer-Encoding: 7bit

  #cloud-config
  cloud_final_modules:
  - [scripts-user, always]

  --==BOUNDARY==
  Content-Type: text/x-shellscript; charset="us-ascii"
  MIME-Version: 1.0
  Content-Transfer-Encoding: 7bit

  #!/bin/bash
  export CLUSTER_NAME="${local.name}"
  export CUSTOM_PRE_STARTUP_SCRIPT="${var.CUSTOM_PRE_STARTUP_SCRIPT}"
  export CUSTOM_POST_STARTUP_SCRIPT="${var.CUSTOM_POST_STARTUP_SCRIPT}"
  echo '${base64gzip(file("${path.module}/resources/proxy-startup.sh"))}' | base64 -d | gzip -d > /tmp/proxy-startup.sh
  chmod +x /tmp/proxy-startup.sh
  /tmp/proxy-startup.sh

  --==BOUNDARY==--
  EOT
  )

  # only create the reservation specification if RESERVE_KNFSD_CAPACITY is true
  dynamic "capacity_reservation_specification" {
    for_each = var.RESERVE_KNFSD_CAPACITY ? [1] : []
    content {
      capacity_reservation_target {
        capacity_reservation_id = aws_ec2_capacity_reservation.knfsd_reservation[0].id
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
