# terraform/modules/rds/variables.tf

variable "name" {
  description = "Identifier for the RDS instance"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to place the RDS instance in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group (min 2 AZs)"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to the DB port"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect (use security groups where possible)"
  type        = list(string)
  default     = []
}

variable "engine" {
  description = "Database engine (postgres, mysql, etc.)"
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Database engine version"
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "allocated_storage_gb" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Maximum storage for autoscaling (0 = disabled)"
  type        = number
  default     = 100
}

variable "kms_key_id" {
  description = "KMS key ARN for storage encryption (null = AWS managed key)"
  type        = string
  default     = null
}

variable "database_name" {
  description = "Name of the initial database to create"
  type        = string
}

variable "master_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "master_password" {
  description = "Master password — use AWS Secrets Manager reference in production"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups (7 minimum recommended)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "backup_retention_days must be at least 7 for production readiness."
  }
}

variable "backup_window" {
  description = "Preferred backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "deletion_protection" {
  description = "Enable deletion protection — set false only to destroy the instance"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (set true only for dev/test)"
  type        = bool
  default     = false
}

variable "parameter_group_family" {
  description = "DB parameter group family"
  type        = string
  default     = "postgres15"
}

variable "db_parameters" {
  description = "List of DB parameters to apply"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "cloudwatch_log_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = ["postgresql", "upgrade"]
}

variable "enable_performance_insights" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources — must include Team, Owner, Environment, CostCenter"
  type        = map(string)

  validation {
    condition = alltrue([
      contains(keys(var.tags), "Team"),
      contains(keys(var.tags), "Owner"),
      contains(keys(var.tags), "Environment"),
      contains(keys(var.tags), "CostCenter")
    ])
    error_message = "tags must include: Team, Owner, Environment, CostCenter."
  }
}
