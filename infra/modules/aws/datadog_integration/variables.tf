variable "role_name" {
  description = "Name of the IAM role for Datadog integration"
  type        = string
}

variable "external_id" {
  description = "Datadog-generated External ID (from datadog_integration_aws_account) required in the role's trust policy"
  type        = string
}

# Must be known at plan time, because the ARNs become for_each keys. ARNs read
# from SSM data sources satisfy this.
variable "policy_arns" {
  description = "ARNs of the managed policies granting the role its permissions, owned by live/shared/iam-github-oidc. SecurityAudit is attached in addition."
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}
