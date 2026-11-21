variable "aws_region" {
  description = "AWS region. The analyzers are Regional, so they cover resources in this Region only; the trail records every Region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used for tagging"
  type        = string
  default     = "shared"
}

variable "project" {
  description = "Project name, used for resource naming and tagging. The pipeline role's grants are scoped to this prefix."
  type        = string
  default     = "internal-developer-platform"
}

variable "unused_access_age_days" {
  description = "Days a role, key or permission must go unused before the unused-access analyzer reports it"
  type        = number
  default     = 90

  validation {
    condition     = var.unused_access_age_days >= 1 && var.unused_access_age_days <= 365
    error_message = "unused_access_age_days must be between 1 and 365."
  }
}

variable "enable_cloudtrail" {
  description = "Create the account trail. Set false where a trail recording management events in every Region already exists outside this stack, since a second copy of management events is billed."
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = "Days the trail's log files are kept in S3"
  type        = number
  default     = 365
}
