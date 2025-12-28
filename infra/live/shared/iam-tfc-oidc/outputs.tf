output "tfc_oidc_role_arn" {
  description = "ARN of the IAM role assumed by Terraform Cloud via OIDC"
  value       = module.tfc_oidc.role_arn
}

output "tfc_oidc_provider_arn" {
  description = "ARN of the OIDC provider for Terraform Cloud"
  value       = module.tfc_oidc.oidc_provider_arn
}
