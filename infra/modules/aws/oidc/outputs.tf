output "oidc_provider_arn" {
  description = "ARN of the OIDC provider, referenced as the Federated principal in role trust policies"
  value       = aws_iam_openid_connect_provider.this.arn
}
