variable "role_name" {
  description = "Name of the IAM role to create"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of an existing IAM OIDC provider the role trusts"
  type        = string
}

variable "string_equals" {
  description = "Map of StringEquals conditions for the assume role policy"
  type        = map(any)
  default     = {}
}

variable "string_like" {
  description = "Map of StringLike conditions for the assume role policy"
  type        = map(any)
  default     = {}
}

variable "policy_arns" {
  description = "Policy ARNs to attach to the role (use least privilege)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the role"
  type        = map(string)
  default     = {}
}
