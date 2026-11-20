output "app_url" {
  description = "Open this in your browser."
  value       = local.https_enabled ? "https://${var.domain_name}" : "http://${aws_lb.app.dns_name}"
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "cloudfront_domain" {
  description = "CDN domain serving /static/* from S3."
  value       = aws_cloudfront_distribution.static.domain_name
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "rds_endpoint" {
  value = aws_db_instance.this.address
}

output "db_secret_arn" {
  description = "Secrets Manager secret holding the DB credentials (managed and rotated by RDS)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "waf_web_acl_name" {
  value = aws_wafv2_web_acl.app.name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "vpc_id" {
  value = aws_vpc.this.id
}
