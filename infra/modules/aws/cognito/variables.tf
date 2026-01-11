variable "user_pool_name" {
  description = "The name of the Cognito User Pool"
  type        = string
}
variable "environment" {
  description = "Environment name (e.g., prod, staging, dev) used for resource naming and tagging"
  type        = string
}

variable "project" {
  description = "Project name used for tagging"
  type        = string
}

variable "tags" {
  description = "A mapping of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
