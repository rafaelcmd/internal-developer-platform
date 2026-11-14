variable "role_name" {
  description = "Name of the IAM role to create"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of an existing IAM OIDC provider the role trusts"
  type        = string
}

variable "string_equals" {
  description = "StringEquals trust conditions: claim key to the list of accepted values. A key matches if any value does; all keys must match."
  type        = map(list(string))
  default     = {}
}

variable "string_like" {
  description = "StringLike trust conditions, for claims that need a wildcard: claim key to the list of accepted patterns"
  type        = map(list(string))
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
