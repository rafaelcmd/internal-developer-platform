variable "url" {
  description = "OIDC provider URL (e.g., https://token.actions.githubusercontent.com)"
  type        = string
}

variable "client_id_list" {
  description = "List of client IDs (audiences) the provider accepts"
  type        = list(string)
}

variable "thumbprint" {
  description = "The thumbprint for the OIDC provider (see AWS docs for current value)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the provider"
  type        = map(string)
  default     = {}
}
