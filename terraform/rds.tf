resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
  tags       = { Name = "${local.name}-db-subnets" }
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-mysql"
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100 # storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true # encryption at rest (aws/rds KMS key)

  db_name  = var.db_name
  username = var.db_username
  # RDS generates the password, stores it in Secrets Manager and rotates it.
  # No password ever appears in Terraform code, state or user data.
  manage_master_user_password = true

  multi_az               = var.db_multi_az # synchronous standby in the 2nd AZ + automatic failover
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period         = var.db_backup_retention_days
  backup_window                   = "03:00-04:00"
  maintenance_window              = "sun:04:30-sun:05:30"
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = true # learning project - change to false for real workloads
  apply_immediately   = true

  tags = { Name = "${local.name}-mysql" }
}
