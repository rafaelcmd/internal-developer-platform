output "role_name" {
  description = "Name of the created IAM role"
  value       = aws_iam_role.datadog_integration_role.name
}

output "role_arn" {
  description = "ARN of the created IAM role"
  value       = aws_iam_role.datadog_integration_role.arn
}

output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "partition" {
  description = "AWS Partition"
  value       = data.aws_partition.current.partition
}
