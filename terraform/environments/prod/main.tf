# terraform/environments/prod/main.tf
# Production environment — full HA, strict security, deletion protection everywhere

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "alias/terraform-state-key"
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  environment = "prod"
  name_prefix = "myapp-${local.environment}"

  common_tags = {
    Environment = local.environment
    Team        = var.team
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "Terraform"
    Repo        = "github.com/my-org/iac-governance-platform"
  }
}

# ─────────────────────────────────────────────
# VPC — full HA across 3 AZs
# ─────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  name               = local.name_prefix
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_nat_gateway = true  # NAT per AZ for high availability

  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]

  flow_log_retention_days = 365  # 1 year for compliance

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Application EC2 Layer — Multi-AZ ASG
# ─────────────────────────────────────────────
module "app" {
  source = "../../modules/ec2"

  name             = "${local.name_prefix}-app"
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.private_subnet_ids
  ami_id           = var.app_ami_id
  instance_type    = "m5.large"   # Production-grade instance
  min_size         = 2            # Minimum 2 for HA
  max_size         = 10
  desired_capacity = 2

  ingress_rules = [{
    description     = "HTTP from within VPC only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    cidr_blocks     = [var.vpc_cidr]
    security_groups = []
  }]

  enable_autoscaling       = true
  scale_up_cpu_threshold   = 60   # More aggressive scaling in prod
  scale_down_cpu_threshold = 15

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# RDS — Multi-AZ, encrypted with CMK, full backups
# ─────────────────────────────────────────────
module "db" {
  source = "../../modules/rds"

  name       = "${local.name_prefix}-db"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r5.large"  # Memory-optimized for production

  database_name   = "myapp"
  master_username = "dbadmin"
  master_password = var.db_password

  allocated_storage_gb     = 100
  max_allocated_storage_gb = 500
  kms_key_id               = var.db_kms_key_arn  # Customer-managed KMS key

  multi_az              = true   # HA — automatic failover
  backup_retention_days = 30     # 30-day backup window for prod
  backup_window         = "02:00-03:00"
  maintenance_window    = "Sun:03:00-Sun:04:00"
  deletion_protection   = true   # Cannot be destroyed without explicit override
  skip_final_snapshot   = false  # Always take final snapshot

  enable_performance_insights = true

  db_parameters = [
    { name = "log_min_duration_statement", value = "1000" },  # Log slow queries > 1s
    { name = "log_connections",            value = "1" },
    { name = "log_disconnections",         value = "1" },
  ]

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Artifact & Asset Storage
# ─────────────────────────────────────────────
module "artifacts" {
  source = "../../modules/s3"

  bucket_name        = "myapp-${local.environment}-artifacts-${data.aws_caller_identity.current.account_id}"
  versioning_enabled = true
  kms_key_id         = var.s3_kms_key_arn
  force_destroy      = false  # Never force destroy prod buckets

  lifecycle_rules = [{
    id              = "archive-to-glacier"
    expiration_days = null  # Never expire — archive instead
    transitions = [
      { days = 90,  storage_class = "STANDARD_IA" },
      { days = 365, storage_class = "GLACIER" }
    ]
  }]

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}
