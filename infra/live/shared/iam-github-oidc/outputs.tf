output "github_actions_oidc_provider_arn" {
  description = "ARN of the OIDC provider for GitHub Actions"
  value       = module.github_actions_oidc.oidc_provider_arn
}

# Copy this value into the AWS_PLAN_ROLE_ARN repository Actions variable after
# apply. Pull-request plan runs assume it.
output "github_actions_plan_role_arn" {
  description = "ARN of the read-only IAM role assumed by pull-request plan runs"
  value       = aws_iam_role.github_actions_plan.arn
}

# Workflows derive these ARNs from the naming convention rather than reading
# them, so these outputs exist for verification and for the EKS access-entry
# list in api/dev.tfvars.
output "component_role_arns" {
  description = "ARNs of the per-component Terraform pipeline roles, keyed by component"
  value       = { for k, m in module.component_roles : k => m.role_arn }
}

output "deploy_role_arn" {
  description = "ARN of the IAM role assumed by workload deploy workflows"
  value       = module.deploy_role.role_arn
}

output "workload_boundary_arn" {
  description = "ARN of the permissions boundary every workload role must carry; also published to SSM for the component stacks"
  value       = aws_iam_policy.workload_boundary.arn
}

output "datadog_integration_policy_arn" {
  description = "ARN of the managed policy granting the Datadog integration role its permissions; also published to SSM"
  value       = aws_iam_policy.datadog_integration.arn
}
