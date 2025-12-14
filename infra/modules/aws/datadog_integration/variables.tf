variable "role_name" {
  description = "Name of the IAM role for Datadog integration"
  type        = string
}

variable "external_id" {
  description = "External ID for Datadog integration role"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}
