output "trail_arn" {
  description = "ARN of the trail"
  value       = aws_cloudtrail.this.arn
}

output "bucket_name" {
  description = "Name of the S3 bucket holding the delivered log files"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket holding the delivered log files"
  value       = aws_s3_bucket.this.arn
}
