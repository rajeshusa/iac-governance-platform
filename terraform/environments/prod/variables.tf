# terraform/environments/prod/variables.tf

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "app_ami_id" {
  description = "AMI ID for application servers"
  type        = string
}

variable "db_password" {
  description = "RDS master password — injected from GitHub Secret / AWS Secrets Manager"
  type        = string
  sensitive   = true
}

variable "db_kms_key_arn" {
  description = "Customer-managed KMS key ARN for RDS encryption"
  type        = string
}

variable "s3_kms_key_arn" {
  description = "Customer-managed KMS key ARN for S3 encryption"
  type        = string
}

variable "team" {
  type = string
}

variable "owner" {
  type = string
}

variable "cost_center" {
  type = string
}
