output "table_name" {
  description = "Name of the scaffolder's single DynamoDB table"
  value       = aws_dynamodb_table.scaffolder.name
}

output "table_arn" {
  description = "ARN of the scaffolder's single DynamoDB table"
  value       = aws_dynamodb_table.scaffolder.arn
}

output "task_queue_name" {
  description = "Name of the task queue the worker consumes — the value the Deployment sets as SCAFFOLDER_TASK_QUEUE_NAME"
  value       = aws_sqs_queue.tasks.name
}

output "task_queue_arn" {
  description = "ARN of the task queue — the target the scaffold state machine's .waitForTaskToken states send to"
  value       = aws_sqs_queue.tasks.arn
}

output "task_dlq_arn" {
  description = "ARN of the task dead-letter queue"
  value       = aws_sqs_queue.tasks_dlq.arn
}

output "irsa_role_arn" {
  description = "ARN of the role the scaffolder pod assumes"
  value       = aws_iam_role.scaffolder.arn
}
