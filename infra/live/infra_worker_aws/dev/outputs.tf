output "task_queue_name" {
  description = "Name of the worker's task queue: the TASK_QUEUE_NAME the Deployment sets and the queue the ProvisionInfra state targets"
  value       = module.task_queue.queue_name
}

output "task_queue_arn" {
  description = "ARN of the worker's task queue"
  value       = module.task_queue.queue_arn
}

output "task_dlq_arn" {
  description = "ARN of the dead-letter queue tasks land in after task_max_receive_count deliveries"
  value       = module.task_queue.dlq_arn
}

output "irsa_role_arn" {
  description = "ARN of the IAM role the worker pod assumes"
  value       = module.irsa.role_arn
}

output "service_account_name" {
  description = "ServiceAccount the worker Deployment binds to (k8s/infra-worker-aws/deployment.yaml)"
  value       = module.irsa.service_account_name
}
