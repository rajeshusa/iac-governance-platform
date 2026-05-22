# terraform/modules/s3/variables.tf

variable "bucket_name" {
  description = "Name of the S3 bucket (must be globally unique)"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable versioning on the bucket"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ARN for SSE-KMS encryption (null = AES256)"
  type        = string
  default     = null
}

variable "access_log_bucket" {
  description = "Bucket name to send S3 access logs to (null = disabled)"
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even if non-empty (dev only)"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for object transitions and expiry"
  type = list(object({
    id              = string
    expiration_days = optional(number)
    transitions = list(object({
      days          = number
      storage_class = string
    }))
  }))
  default = []
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
