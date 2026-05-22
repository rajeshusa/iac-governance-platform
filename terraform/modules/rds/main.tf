# terraform/modules/rds/main.tf
# Governance-compliant RDS module
# Enforces: encryption, no public access, automated backups, deletion protection

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ─────────────────────────────────────────────
# Subnet Group — private subnets only
# ─────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name        = "${var.name}-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for ${var.name} RDS instance"

  tags = merge(var.tags, {
    Name = "${var.name}-subnet-group"
  })
}

# ─────────────────────────────────────────────
# Security Group — only accept traffic from app layer
# ─────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Security group for ${var.name} RDS — app tier access only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "DB port from app security group"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    cidr_blocks     = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-rds-sg"
  })
}

# ─────────────────────────────────────────────
# Parameter Group
# ─────────────────────────────────────────────
resource "aws_db_parameter_group" "main" {
  name        = "${var.name}-params"
  family      = var.parameter_group_family
  description = "Parameter group for ${var.name}"

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────
# RDS Instance
# Governance enforcements:
#   - storage_encrypted = true          (OPA Policy-004)
#   - publicly_accessible = false       (Checkov CKV_AWS_23)
#   - backup_retention_period >= 7      (operational requirement)
#   - deletion_protection = true        (production safety)
#   - multi_az = true (prod)            (HA requirement)
# ─────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier = var.name

  # Engine
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class
  port           = var.port

  # Storage
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb  # Enables autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true   # Always encrypted — OPA Policy-004
  kms_key_id            = var.kms_key_id

  # Database
  db_name  = var.database_name
  username = var.master_username
  password = var.master_password  # Should come from AWS Secrets Manager in prod

  # Network — NEVER publicly accessible
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # Checkov CKV_AWS_23

  # High availability
  multi_az = var.multi_az

  # Backups
  backup_retention_period   = var.backup_retention_days
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false

  # Monitoring
  monitoring_interval             = 60  # Enhanced monitoring every 60s
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = var.cloudwatch_log_exports
  performance_insights_enabled    = var.enable_performance_insights

  # Parameter group
  parameter_group_name = aws_db_parameter_group.main.name

  # Safety
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"

  # Auto minor version upgrades
  auto_minor_version_upgrade = true
  apply_immediately          = false  # Never apply changes immediately in prod

  tags = merge(var.tags, {
    Name = var.name
  })
}

# ─────────────────────────────────────────────
# Enhanced Monitoring IAM Role
# ─────────────────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─────────────────────────────────────────────
# CloudWatch Alarms
# ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU above 80%"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "storage_low" {
  alarm_name          = "${var.name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120  # 5 GB in bytes
  alarm_description   = "RDS free storage below 5GB"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = var.tags
}
