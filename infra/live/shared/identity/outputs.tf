output "user_pool_id" {
  description = "ID of the Cognito user pool"
  value       = module.cognito.user_pool_id
}

output "user_pool_arn" {
  description = "ARN of the Cognito user pool"
  value       = module.cognito.user_pool_arn
}

output "user_pool_client_id" {
  description = "ID of the Cognito user pool client"
  value       = module.cognito.user_pool_client_id
}
