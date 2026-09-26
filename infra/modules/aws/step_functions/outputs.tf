output "state_machine_arn" {
  description = "ARN of the state machine, which is what StartExecution takes and what IAM policies are written against"
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "Name of the state machine"
  value       = aws_sfn_state_machine.this.name
}

output "role_arn" {
  description = "ARN of the execution role the machine assumes when it calls the services its states target"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the execution role"
  value       = aws_iam_role.this.name
}

output "log_group_name" {
  description = "Name of the log group execution history is delivered to"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the execution-history log group"
  value       = aws_cloudwatch_log_group.this.arn
}

output "failure_alarm_arn" {
  description = "ARN of the failed-execution alarm, or null when it was not created"
  value       = one(aws_cloudwatch_metric_alarm.executions_failed[*].arn)
}
