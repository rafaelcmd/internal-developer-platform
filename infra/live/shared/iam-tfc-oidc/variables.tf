variable "environment" {
  description = "Environment name (e.g., prod, staging, dev) used for resource naming and tagging"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used for tagging"
  type        = string
  default     = "internal-developer-platform"
}

variable "aws_region" {
  description = "AWS region where the IAM resources will be managed"
  type        = string
  default     = "us-east-1"
}
