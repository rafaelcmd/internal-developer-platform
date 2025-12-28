variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}
variable "github_thumbprint" {
  description = "The thumbprint for GitHub OIDC provider (see AWS docs for current value)"
  type        = string
}

variable "github_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions via OIDC"
  type        = string
}

variable "github_allowed_subs" {
  description = "List of allowed OIDC subject claims for GitHub Actions (e.g., repo:org/repo:ref:branch)"
  type        = list(string)
}

variable "github_policy_arns" {
  description = "Policy ARNs to attach to the GitHub Actions OIDC role (use least privilege)"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
