variable "aws_region" {
  description = "AWS region to create resources in"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "shared"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "internal-developer-platform"
}
