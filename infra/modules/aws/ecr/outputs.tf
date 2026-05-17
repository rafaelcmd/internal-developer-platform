output "repository_name" {
  description = "The name of the repository"
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "The URL of the repository"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "The ARN of the repository"
  value       = aws_ecr_repository.this.arn
}

output "repository_url_ssm_parameter_name" {
  description = "The name of the SSM parameter holding the repository URL"
  value       = aws_ssm_parameter.repository_url.name
}
