# terraform/environments/staging/variables.tf

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "app_ami_id" {
  description = "AMI ID for application servers"
  type        = string
}

variable "db_password" {
  description = "RDS master password — injected from GitHub Secret"
  type        = string
  sensitive   = true
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
