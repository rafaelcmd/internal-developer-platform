# =============================================================================
# API GATEWAY OUTPUTS
# =============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = module.api_gateway.api_gateway_id
}

output "api_gateway_invoke_url" {
  description = "Invoke URL of the API Gateway"
  value       = module.api_gateway.api_gateway_invoke_url
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = module.api_gateway.api_gateway_execution_arn
}

output "vpc_link_id" {
  description = "ID of the VPC Link"
  value       = module.api_gateway.vpc_link_id
}

# =============================================================================
# COGNITO OUTPUTS
# =============================================================================

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool used as the API Gateway authorizer"
  value       = module.cognito.user_pool_arn
}

# =============================================================================
# NLB LOOKUP (passthrough — useful for debugging the integration)
# =============================================================================

output "nlb_arn" {
  description = "ARN of the NLB the VPC Link targets"
  value       = data.aws_lb.api.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB the VPC Link targets"
  value       = data.aws_lb.api.dns_name
}
