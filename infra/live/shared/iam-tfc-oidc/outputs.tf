output "tfc_oidc_provider_arn" {
  description = "ARN of the OIDC provider for Terraform Cloud"
  value       = module.tfc_oidc.oidc_provider_arn
}
