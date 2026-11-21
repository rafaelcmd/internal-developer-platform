output "external_access_analyzer_arn" {
  description = "ARN of the analyzer that reports access from outside this account"
  value       = aws_accessanalyzer_analyzer.external_access.arn
}

output "unused_access_analyzer_arn" {
  description = "ARN of the analyzer that reports unused roles, keys and permissions"
  value       = aws_accessanalyzer_analyzer.unused_access.arn
}

output "cloudtrail_trail_arn" {
  description = "ARN of the account trail, or null when enable_cloudtrail is false"
  value       = one(module.cloudtrail[*].trail_arn)
}

output "cloudtrail_bucket_name" {
  description = "Name of the bucket holding the trail's log files, or null when enable_cloudtrail is false"
  value       = one(module.cloudtrail[*].bucket_name)
}
