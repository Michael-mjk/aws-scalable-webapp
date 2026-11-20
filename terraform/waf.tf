locals {
  # AWS managed rule groups (covers most of the OWASP Top 10 surface)
  waf_managed_rules = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 0 }, # known bad IPs / bots
    { name = "AWSManagedRulesCommonRuleSet", priority = 1 },          # XSS, LFI, RFI, bad sizes...
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 2 },  # Log4j, invalid patterns
    { name = "AWSManagedRulesSQLiRuleSet", priority = 3 },            # SQL injection
  ]
}

resource "aws_wafv2_web_acl" "app" {
  name        = "${local.name}-waf"
  description = "Protects the public ALB"
  scope       = "REGIONAL" # REGIONAL = ALB / API Gateway, CLOUDFRONT = distributions

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.waf_managed_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {} # use the group's own block actions
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.name
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}
