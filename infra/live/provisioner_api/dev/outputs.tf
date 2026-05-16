# =============================================================================
# EKS OUTPUTS
# Consumed by the edge stack (infra/live/provisioner_api_gateway/dev) and by
# operators running kubectl against the cluster.
# =============================================================================

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API server endpoint of the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider — needed when minting IRSA roles for workloads"
  value       = module.eks.oidc_provider_arn
}

# =============================================================================
# DATADOG INTEGRATION OUTPUTS
# =============================================================================

output "datadog_forwarder_arn" {
  description = "The ARN of the Datadog Lambda forwarder"
  value       = module.datadog_forwarder.datadog_forwarder_arn
}

output "datadog_forwarder_name" {
  description = "The name of the Datadog Lambda forwarder"
  value       = module.datadog_forwarder.function_name
}
