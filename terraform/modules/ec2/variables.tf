# terraform/modules/ec2/variables.tf

variable "name" {
  description = "Name prefix for all EC2 resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to launch instances into"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ASG (private subnets recommended)"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"

  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge",
      "r5.large", "r5.xlarge", "r5.2xlarge"
    ], var.instance_type)
    error_message = "instance_type must be in the org-approved list. Submit an exception for larger sizes."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of instances"
  type        = number
  default     = 1
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "kms_key_id" {
  description = "KMS key ARN for EBS encryption (null = AWS managed key)"
  type        = string
  default     = null
}

variable "ingress_rules" {
  description = "List of ingress rules for the security group"
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = list(string)
    security_groups = optional(list(string), [])
  }))
  default = []
}

variable "target_group_arns" {
  description = "List of ALB/NLB target group ARNs to attach the ASG to"
  type        = list(string)
  default     = null
}

variable "additional_policy_arns" {
  description = "Additional IAM policy ARNs to attach to the instance role"
  type        = list(string)
  default     = []
}

variable "user_data_base64" {
  description = "Base64-encoded user data script"
  type        = string
  default     = null
}

variable "enable_autoscaling" {
  description = "Enable CPU-based auto scaling policies"
  type        = bool
  default     = true
}

variable "scale_up_cpu_threshold" {
  description = "CPU % threshold to trigger scale up"
  type        = number
  default     = 70
}

variable "scale_down_cpu_threshold" {
  description = "CPU % threshold to trigger scale down"
  type        = number
  default     = 20
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
