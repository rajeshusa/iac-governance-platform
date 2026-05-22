# terraform/environments/dev/main.tf
# Development environment — uses governance-compliant modules

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — S3 backend with DynamoDB locking
  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "environments/dev/terraform.tfstate"
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

# ─────────────────────────────────────────────
# Locals
# ─────────────────────────────────────────────
locals {
  environment = "dev"
  name_prefix = "myapp-${local.environment}"

  # Common tags applied to ALL resources via provider default_tags
  # Satisfies OPA Policy-001 (required tags)
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
  enable_nat_gateway = false  # Cost optimization for dev

  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  flow_log_retention_days = 30  # Shorter retention for dev

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Terraform State Bucket (remote state storage)
# ─────────────────────────────────────────────
module "state_bucket" {
  source = "../../modules/s3"

  bucket_name        = "myapp-${local.environment}-terraform-state-${data.aws_caller_identity.current.account_id}"
  versioning_enabled = true
  force_destroy      = false

  tags = local.common_tags
}

# ─────────────────────────────────────────────
# Data Sources
# ─────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
