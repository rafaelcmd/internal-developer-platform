variable "aws_region" {
  description = "AWS region where the IAM resources will be managed"
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository"
  type        = string
  default     = "rafaelcmd"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "internal-developer-platform"
}

variable "github_allowed_refs" {
  description = "List of Git refs (e.g., refs/heads/main) allowed to assume the role"
  type        = list(string)
  default     = [
    "refs/heads/main"
  ]
}

variable "github_actions_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions via OIDC"
  type        = string
  default     = "github-actions-internal-developer-platform"
}

variable "github_actions_policy_arns" {
  description = "Policy ARNs to attach to the GitHub Actions role (use least privilege)"
  type        = list(string)
  default     = [
    "arn:aws:iam::aws:policy/AdministratorAccess"
  ]
}

variable "tags" {
  description = "Tags to apply to created resources"
  type        = map(string)
  default     = {}
}
