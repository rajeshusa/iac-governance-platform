# terraform/environments/dev/variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "team" {
  description = "Team that owns these resources"
  type        = string
}

variable "owner" {
  description = "Owner (email) responsible for these resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing attribution"
  type        = string
}
