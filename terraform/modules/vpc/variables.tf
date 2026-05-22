# terraform/modules/vpc/variables.tf

variable "name" {
  description = "Name prefix for all VPC resources"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet outbound internet access"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch log retention for VPC flow logs"
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 180, 365], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be one of: 30, 60, 90, 120, 180, 365."
  }
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
