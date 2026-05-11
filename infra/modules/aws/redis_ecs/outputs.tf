output "redis_endpoint" {
  description = "host:port address for Redis (resolves via Cloud Map private DNS)"
  value       = local.redis_endpoint
}

output "redis_dns_name" {
  description = "DNS name of the Redis service (without port)"
  value       = local.redis_dns_name
}

output "security_group_id" {
  description = "Security group attached to the Redis service"
  value       = aws_security_group.redis.id
}

output "service_discovery_namespace_id" {
  description = "ID of the Cloud Map private DNS namespace, exposed so other internal services can reuse it"
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "ssm_parameter_name" {
  description = "SSM parameter name where the Redis endpoint is published"
  value       = aws_ssm_parameter.redis_endpoint.name
}
