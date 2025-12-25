# =============================================================================
# AWS CONFIGURATION
# Variables for AWS region and basic deployment configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# =============================================================================
# VPC NETWORK CONFIGURATION
# Variables for VPC and subnet CIDR block configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones to deploy subnets into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# =============================================================================
# PROJECT AND ENVIRONMENT CONFIGURATION
# Variables for project identification and environment setup
# =============================================================================

variable "project" {
  description = "Name of the project"
  type        = string
  default     = "internal-developer-platform"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

# =============================================================================
# RESOURCE TAGGING
# Variables for resource tagging and labeling
# =============================================================================

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
