# =============================================================================
# DATADOG AWS INTEGRATION OUTPUTS
# Outputs for Datadog AWS integration role and authentication
# =============================================================================

output "datadog_integration_role_arn" {
  description = "ARN of the Datadog integration IAM role"
  value       = module.aws_integration.role_arn
}

output "datadog_integration_external_id" {
  description = "External ID for Datadog integration"
  value       = var.external_id
  sensitive   = true
}
