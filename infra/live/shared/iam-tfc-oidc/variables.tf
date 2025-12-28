variable "aws_region" {
  description = "AWS region where the IAM resources will be managed"
  type        = string
  default     = "us-east-1"
}

variable "tfc_thumbprint" {
  description = "The thumbprint for Terraform Cloud OIDC provider (see AWS docs for current value)"
  type        = string
}

variable "tfc_role_name" {
  description = "Name of the IAM role assumed by Terraform Cloud via OIDC"
  type        = string
  default     = "tfc-oidc-internal-developer-platform"
}

variable "tfc_allowed_subs" {
  description = "List of allowed OIDC subject claims for Terraform Cloud (e.g., org/workspace/user)"
  type        = list(string)
}

variable "tfc_policy_arns" {
  description = "Policy ARNs to attach to the TFC OIDC role (use least privilege)"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to created resources"
  type        = map(string)
  default     = {}
}
