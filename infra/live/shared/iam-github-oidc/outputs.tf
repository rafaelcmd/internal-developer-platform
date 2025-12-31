output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC"
  value       = module.github_actions_oidc.role_arn
}

output "github_actions_oidc_provider_arn" {
  description = "ARN of the OIDC provider for GitHub Actions"
  value       = module.github_actions_oidc.oidc_provider_arn
}
