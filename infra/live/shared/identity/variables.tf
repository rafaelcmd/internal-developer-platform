variable "aws_region" {
  description = "AWS region"
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

variable "user_pool_name" {
  description = "Cognito user pool name"
  type        = string
  default     = "internal-developer-platform-user-pool"
}
