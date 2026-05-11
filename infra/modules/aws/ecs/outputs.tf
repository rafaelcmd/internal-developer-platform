output "api_task_security_group_id" {
  description = "Security group attached to the API ECS task — used to allow egress to internal services like Redis."
  value       = aws_security_group.api_ecs_task_sg.id
}

output "cluster_id" {
  description = "ID of the ECS cluster, so other services can attach to the same cluster."
  value       = aws_ecs_cluster.internal_developer_platform_cluster.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.internal_developer_platform_cluster.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.internal_developer_platform_cluster.name
}
