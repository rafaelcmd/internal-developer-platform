# =============================================================================
# AWS CONFIGURATION
# Variables for AWS region and deployment configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# =============================================================================
# IAM ROLE CONFIGURATION
# Variables for Datadog AWS integration IAM role setup
# =============================================================================

variable "role_name" {
  description = "Name of the IAM role for Datadog integration"
  type        = string
  default     = "DatadogIntegrationRole"
}

variable "external_id" {
  description = "External ID for Datadog integration role"
  type        = string
  default     = "datadog-integration-external-id"
}

# =============================================================================
# PROJECT AND ENVIRONMENT CONFIGURATION
# Variables for project identification and environment setup
# =============================================================================

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
