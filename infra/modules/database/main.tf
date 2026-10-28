# RDS PostgreSQL. Managed > self-hosted on EKS for prod: AWS owns patching, backups,
# PITR and Multi-AZ failover, so a small team doesn't have to be DBAs.
# (Locally CloudNativePG gives the same contract for $0.)

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "db" {
  description             = "${var.name} RDS storage + Performance Insights + secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  # Explicit policy: key administration stays with the account (IAM decides who);
  # services use it through their own IAM permissions (e.g. External Secrets kms:Decrypt).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdministration"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
  tags = var.tags
}

# Enhanced Monitoring: OS-level metrics (CPU steal, memory, IO) at 1-60s granularity.
resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0
  name  = "${var.name}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "monitoring.rds.amazonaws.com" } }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  description = "Postgres access from EKS nodes only"
  vpc_id      = var.vpc_id
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Pods use the node security group (VPC CNI without SG-for-pods), so allow that SG -
# never a CIDR. Inside the cluster, NetworkPolicy narrows it further to api/collector/migrations.
resource "aws_vpc_security_group_ingress_rule" "from_nodes" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "EKS nodes"
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg16-"
  family      = "postgres16"
  tags        = var.tags

  parameter {
    name  = "rds.force_ssl"
    value = "1" # reject unencrypted connections
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log queries slower than 500ms
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_157:multi_az is a variable - true in prod, false in dev by design (cost)
  #checkov:skip=CKV_AWS_293:deletion_protection is a variable - true in prod, false in dev so it can be torn down
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = "weather"
  username = "weather_admin"
  # RDS generates + rotates the password in Secrets Manager. It never appears in
  # Terraform state, CI logs or Git.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.db.arn

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 5 # storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.db.arn

  db_subnet_group_name   = var.db_subnet_group
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = !var.deletion_protection
  final_snapshot_identifier  = var.deletion_protection ? "${var.name}-final" : null

  # Enables IAM auth (short-lived tokens instead of passwords) - app migration is a follow-up.
  iam_database_authentication_enabled = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.db.arn
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = var.tags
}
