# Copyright 2020 Google LLC
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

resource "aws_autoscaling_policy" "scale_up_policy" {
  count                  = var.ENABLE_KNFSD_AUTOSCALING ? 1 : 0
  name                   = "${local.name}-asg-policy-scale-up"
  autoscaling_group_name = aws_autoscaling_group.knfsd_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 180
}

resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  count               = var.ENABLE_KNFSD_AUTOSCALING ? 1 : 0
  alarm_name          = "${local.name}-cw-alarm-scale-up"
  alarm_description   = "Alarm if NFS connections average is more than: ${var.KNFSD_AUTOSCALING_NFS_CONNECTIONS_THRESHOLD}"
  actions_enabled     = true
  alarm_actions       = [aws_autoscaling_policy.scale_up_policy[0].arn]
  metric_name         = "knfsd/nfs_connections"
  namespace           = "/knfsd/metrics"
  statistic           = "Average"
  threshold           = var.KNFSD_AUTOSCALING_NFS_CONNECTIONS_THRESHOLD
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.knfsd_asg.name
  }
  tags = local.tags
}

# null resource to ensure ASG is created after the
# FSID DB is available if a DB is being deployed
resource "null_resource" "fsid_db" {
  count      = local.deploy_fsid_database ? 1 : 0
  depends_on = [module.fsid_database[0]]
}

# null resource to ensure ASG is created after the
# Lambda 'static_ip' function is deployed if using DNS RR
resource "null_resource" "dns_rr" {
  count      = var.TRAFFIC_MODE == "dns_round_robin" ? 1 : 0
  depends_on = [module.dns_round_robin[0]]
}

# EC2 Auto Scaling Group for the KNFSD instances
resource "aws_autoscaling_group" "knfsd_asg" {
  depends_on = [
    null_resource.fsid_db,
    null_resource.dns_rr,
    null_resource.autoscaling_slr,
    aws_ssm_parameter.settings,
  ]
  name                      = local.asg_name
  min_size                  = var.ENABLE_KNFSD_AUTOSCALING ? var.KNFSD_AUTOSCALING_MIN_INSTANCES : var.KNFSD_NODES
  max_size                  = var.ENABLE_KNFSD_AUTOSCALING ? var.KNFSD_AUTOSCALING_MAX_INSTANCES : var.KNFSD_NODES
  desired_capacity          = var.ENABLE_KNFSD_AUTOSCALING ? null : var.KNFSD_NODES
  wait_for_capacity_timeout = "0" # avoid rare ASG waiter false-negative from eventual consistency
  default_cooldown          = 30
  default_instance_warmup   = 300 # instance_refresh will use this setting if not overridden
  vpc_zone_identifier       = [var.SUBNET]
  health_check_type         = "EC2"
  health_check_grace_period = var.HEALTHCHECK_INITIAL_DELAY_SECONDS

  target_group_arns = var.TRAFFIC_MODE == "loadbalancer" ? [
    for key, value in var.NFS_PORTS : module.loadbalancer[0].lb_target_groups[key]
  ] : []

  # instance maintenance policy only applies to instance maintenance events
  # only replace one instance at a time
  # if "dns_round_robin" is used: terminate_before_launch
  # otherwise: launch_before_terminate
  instance_maintenance_policy {
    min_healthy_percentage = var.TRAFFIC_MODE == "dns_round_robin" ? 0 : 100
    max_healthy_percentage = 100
  }

  # instance_refresh is triggered when "compute.tf/aws_launch_template" is modified
  # same behaviour as instance_maintenance_policy above
  instance_refresh {
    strategy = "Rolling"
    preferences {
      skip_matching = true
    }
  }

  dynamic "initial_lifecycle_hook" {
    for_each = var.TRAFFIC_MODE == "dns_round_robin" ? [1] : []
    content {
      name                 = "launching-hook"
      default_result       = "ABANDON"
      heartbeat_timeout    = 300
      lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    }
  }

  dynamic "initial_lifecycle_hook" {
    for_each = var.TRAFFIC_MODE == "dns_round_robin" ? [1] : []
    content {
      name                 = "terminating-hook"
      default_result       = "ABANDON"
      heartbeat_timeout    = 300
      lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
    }
  }

  launch_template {
    id      = aws_launch_template.knfsd_launch_template.id
    version = aws_launch_template.knfsd_launch_template.latest_version
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  tag {
    key                 = "Name"
    value               = local.asg_name
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.asg_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  timeouts {
    delete = "20m" # increase from default 10m to 20m
  }
}

# null resource to ensure ASG is destroyed before the
# Lambda 'static_ip' resources are destroyed, if using DNS RR
resource "null_resource" "asg_lambda_dependency" {
  count = var.TRAFFIC_MODE == "dns_round_robin" ? 1 : 0

  triggers = {
    asg_id           = aws_autoscaling_group.knfsd_asg.id
    lambda_resources = jsonencode(module.dns_round_robin[0].lambda_static_ip_resources)
  }

  depends_on = [aws_autoscaling_group.knfsd_asg, module.dns_round_robin[0]]
}
