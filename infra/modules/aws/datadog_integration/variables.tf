variable "role_name" {
  description = "Name of the IAM role for Datadog integration"
  type        = string
}

variable "external_id" {
  description = "Datadog-generated External ID (from datadog_integration_aws_account) required in the role's trust policy"
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
