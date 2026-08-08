output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC"
  value       = module.github_actions_oidc.role_arn
}

output "github_actions_oidc_provider_arn" {
  description = "ARN of the OIDC provider for GitHub Actions"
  value       = module.github_actions_oidc.oidc_provider_arn
}

# Copy this value into the AWS_PLAN_ROLE_ARN repo Actions variable after
# apply; pull-request plan runs assume it.
output "github_actions_plan_role_arn" {
  description = "ARN of the read-only IAM role assumed by pull-request plan runs"
  value       = aws_iam_role.github_actions_plan.arn
}
