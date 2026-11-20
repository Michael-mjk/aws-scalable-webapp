# Always the latest Amazon Linux 2023 AMI (SSM Agent and AWS CLI preinstalled)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "app" {
  name_prefix            = "${local.name}-lt-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # IMDSv2 only - blocks SSRF-style credential theft
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # 1-minute metrics so scaling reacts faster
  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 10
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    aws_region    = var.aws_region
    db_host       = aws_db_instance.this.address
    db_port       = aws_db_instance.this.port
    db_name       = var.db_name
    db_secret_arn = aws_db_instance.this.master_user_secret[0].secret_arn
    cdn_domain    = aws_cloudfront_distribution.static.domain_name
    index_php     = filebase64("${path.module}/../app/index.php")
    lib_php       = filebase64("${path.module}/../app/lib.php")
    health_php    = filebase64("${path.module}/../app/health.php")
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.default_tags, { Name = "${local.name}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.default_tags, { Name = "${local.name}-app-root" })
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = aws_subnet.app[*].id # private subnets in both AZs
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB" # replace instances the ALB considers unhealthy
  health_check_grace_period = 180
  default_instance_warmup   = 120

  enabled_metrics = [
    "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity",
    "GroupInServiceInstances", "GroupPendingInstances", "GroupTerminatingInstances",
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # Rolling replacement whenever the launch template changes
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity] # let the scaling policies own it
  }

  depends_on = [aws_nat_gateway.this, aws_route_table_association.app]
}

# ---------------------------------------------------------------------------
# Scaling policy 1: Target tracking - keep average CPU around var.cpu_target_value
# (also handles scale-in automatically)
# ---------------------------------------------------------------------------
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

# ---------------------------------------------------------------------------
# Scaling policy 2: Step scaling - aggressive scale-out on sudden spikes.
# When several policies fire, the ASG picks the one giving the largest capacity.
# ---------------------------------------------------------------------------
resource "aws_autoscaling_policy" "cpu_step_scale_out" {
  name                      = "${local.name}-cpu-step-scale-out"
  autoscaling_group_name    = aws_autoscaling_group.app.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 120

  # Bounds are relative to the alarm threshold (default 75%)
  step_adjustment { # 75% - 90% -> +1 instance
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 15
    scaling_adjustment          = 1
  }

  step_adjustment { # > 90% -> +2 instances
    metric_interval_lower_bound = 15
    scaling_adjustment          = 2
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  alarm_name          = "${local.name}-asg-cpu-high"
  alarm_description   = "ASG average CPU above ${var.cpu_step_threshold}% - triggers step scale-out"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.cpu_step_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_autoscaling_policy.cpu_step_scale_out.arn, aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
