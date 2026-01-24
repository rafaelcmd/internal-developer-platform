# =============================================================================
# API GATEWAY OUTPUTS
# Outputs for API Gateway identification and access
# =============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.this.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway"
  value       = aws_apigatewayv2_api.this.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "api_gateway_invoke_url" {
  description = "Invoke URL of the API Gateway stage"
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "api_gateway_api_endpoint" {
  description = "API endpoint URL of the API Gateway"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

# =============================================================================
# VPC LINK OUTPUTS
# Outputs for VPC Link identification
# =============================================================================

output "vpc_link_id" {
  description = "ID of the VPC Link"
  value       = aws_apigatewayv2_vpc_link.this.id
}

output "vpc_link_security_group_id" {
  description = "ID of the VPC Link Security Group"
  value       = length(aws_security_group.vpc_link) > 0 ? aws_security_group.vpc_link[0].id : null
}

# =============================================================================
# STAGE OUTPUTS
# Outputs for API Gateway stage information
# =============================================================================

output "stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_apigatewayv2_stage.this.name
}

output "stage_arn" {
  description = "ARN of the API Gateway stage"
  value       = aws_apigatewayv2_stage.this.arn
}

# =============================================================================
# API VERSION OUTPUTS
# Outputs for API versioning information
# =============================================================================

output "api_version" {
  description = "Current API version"
  value       = var.api_version
}

output "api_base_path" {
  description = "Base path for the current API version (e.g., /v1)"
  value       = "/${var.api_version}"
}

output "deprecated_versions" {
  description = "List of deprecated API versions with their sunset dates"
  value       = var.deprecated_versions
}
