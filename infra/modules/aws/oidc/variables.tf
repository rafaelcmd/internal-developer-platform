variable "url" {
  description = "OIDC provider URL (e.g., https://token.actions.githubusercontent.com or https://app.terraform.io)"
  type        = string
}

variable "client_id_list" {
  description = "List of client IDs for the OIDC provider"
  type        = list(string)
}

variable "thumbprint" {
  description = "The thumbprint for the OIDC provider (see AWS docs for current value)"
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role to create"
  type        = string
}

variable "string_equals" {
  description = "Map of StringEquals conditions for the assume role policy"
  type        = map(string)
  default     = {}
}

variable "string_like" {
  description = "Map of StringLike conditions for the assume role policy"
  type        = map(any)
  default     = {}
}

variable "policy_arns" {
  description = "Policy ARNs to attach to the IAM role (use least privilege)"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
