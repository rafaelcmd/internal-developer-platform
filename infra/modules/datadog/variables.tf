variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "role_name" {
  description = "Name of the IAM role for Datadog integration"
  type        = string
  default     = "DatadogIntegrationRole"
}

variable "integration_policy_arns" {
  description = "ARNs of the managed policies attached to the Datadog integration role. Must be known at plan time."
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "internal-developer-platform"
}
