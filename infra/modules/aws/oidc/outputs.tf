output "role_arn" {
  description = "ARN of the IAM role created for OIDC"
  value       = aws_iam_role.this.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.this.arn
}
