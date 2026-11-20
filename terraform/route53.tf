# Everything in this file is created only when var.domain_name is set.

data "aws_route53_zone" "this" {
  count        = local.https_enabled ? 1 : 0
  name         = var.hosted_zone_name
  private_zone = false
}

# ---------------------------------------------------------------------------
# TLS certificate for the ALB (DNS-validated, auto-renewed by ACM)
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "app" {
  count             = local.https_enabled ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.hosted_zone_name != ""
      error_message = "hosted_zone_name must be set when domain_name is set."
    }
  }

  tags = { Name = "${local.name}-cert" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in flatten(aws_acm_certificate.app[*].domain_validation_options) :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  count                   = local.https_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ---------------------------------------------------------------------------
# Alias record -> ALB (free queries, follows ALB IP changes automatically)
# ---------------------------------------------------------------------------
resource "aws_route53_record" "app" {
  count   = local.https_enabled ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------
# Route 53 health check: probes the app from multiple AWS locations worldwide
# ---------------------------------------------------------------------------
resource "aws_route53_health_check" "app" {
  count             = local.https_enabled ? 1 : 0
  fqdn              = var.domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health.php"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${local.name}-health-check" }
}

# Health-check metrics live in us-east-1, and an alarm can only notify an SNS
# topic in its own region - so create a topic there if we deploy elsewhere.
resource "aws_sns_topic" "alerts_use1" {
  count    = local.https_enabled && var.aws_region != "us-east-1" ? 1 : 0
  provider = aws.us_east_1
  name     = "${local.name}-alerts-use1"
}

resource "aws_sns_topic_subscription" "alerts_use1_email" {
  count     = local.https_enabled && var.aws_region != "us-east-1" ? 1 : 0
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts_use1[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  r53_alarm_topic_arn = var.aws_region == "us-east-1" ? aws_sns_topic.alerts.arn : one(aws_sns_topic.alerts_use1[*].arn)
}

resource "aws_cloudwatch_metric_alarm" "route53_health" {
  count               = local.https_enabled ? 1 : 0
  provider            = aws.us_east_1
  alarm_name          = "${local.name}-route53-health-check-failed"
  alarm_description   = "Route 53 cannot reach ${var.domain_name}/health.php"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  dimensions = {
    HealthCheckId = aws_route53_health_check.app[0].id
  }

  alarm_actions = [local.r53_alarm_topic_arn]
  ok_actions    = [local.r53_alarm_topic_arn]
}
