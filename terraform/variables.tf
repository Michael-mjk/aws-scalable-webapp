# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "project_name" {
  description = "Short name used as a prefix for every resource."
  type        = string
  default     = "scalable-webapp"
}

variable "environment" {
  description = "Environment name (prod, staging, dev...)."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address that receives CloudWatch alarm notifications (you must confirm the SNS subscription)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block of the VPC. Subnets are carved out as /24s."
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one NAT Gateway (cheaper, single-AZ egress). false = one NAT Gateway per AZ (fully highly available)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Compute / Auto Scaling
# ---------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type for the web tier."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "cpu_target_value" {
  description = "Target average CPU (%) for the target-tracking scaling policy."
  type        = number
  default     = 50
}

variable "cpu_step_threshold" {
  description = "Average CPU (%) above which the step-scaling policy adds extra instances quickly."
  type        = number
  default     = 75
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
variable "db_engine_version" {
  description = "MySQL major version for RDS."
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial storage in GiB (storage autoscaling is enabled up to 100 GiB)."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Run RDS as Multi-AZ (synchronous standby + automatic failover)."
  type        = bool
  default     = true
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_deletion_protection" {
  description = "Keep false for a learning project so `terraform destroy` works."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Edge / DNS (optional)
# ---------------------------------------------------------------------------
variable "domain_name" {
  description = "Optional FQDN for the app, e.g. app.example.com. Leave empty to use the ALB DNS name over HTTP."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Existing public Route 53 hosted zone that contains domain_name, e.g. example.com. Required when domain_name is set."
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "Max requests per IP in any 5-minute window before WAF blocks the IP."
  type        = number
  default     = 1000
}
