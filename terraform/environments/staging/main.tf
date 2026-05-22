# terraform/environments/staging/main.tf
# Staging environment — production-like config, lower cost settings

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-org-terraform-state-910896516483"
    key            = "environments/staging/terraform.tfstate"
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
  environment = "staging"
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
# VPC
# ─────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  name               = local.name_prefix
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_nat_gateway = true  # Enabled in staging (unlike dev)

  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

  flow_log_retention_days = 60

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Application EC2 Layer
# ─────────────────────────────────────────────
module "app" {
  source = "../../modules/ec2"

  name             = "${local.name_prefix}-app"
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.private_subnet_ids
  ami_id           = var.app_ami_id
  instance_type    = "t3.medium"
  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  ingress_rules = [{
    description     = "HTTP from within VPC"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    cidr_blocks     = [var.vpc_cidr]
    security_groups = []
  }]

  enable_autoscaling       = true
  scale_up_cpu_threshold   = 70
  scale_down_cpu_threshold = 20

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# RDS Database
# ─────────────────────────────────────────────
module "db" {
  source = "../../modules/rds"

  name       = "${local.name_prefix}-db"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.medium"

  database_name   = "myapp"
  master_username = "dbadmin"
  master_password = var.db_password  # Injected from GitHub Secret / SSM

  allocated_storage_gb     = 20
  max_allocated_storage_gb = 100
  multi_az                 = false   # Single-AZ for staging cost savings
  backup_retention_days    = 7
  deletion_protection      = true
  skip_final_snapshot      = false

  enable_performance_insights = true

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Artifact Storage Bucket
# ─────────────────────────────────────────────
module "artifacts" {
  source = "../../modules/s3"

  bucket_name        = "myapp-${local.environment}-artifacts-${data.aws_caller_identity.current.account_id}"
  versioning_enabled = true
  force_destroy      = false

  lifecycle_rules = [{
    id              = "expire-old-artifacts"
    expiration_days = 90
    transitions = [{
      days          = 30
      storage_class = "STANDARD_IA"
    }]
  }]

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}
