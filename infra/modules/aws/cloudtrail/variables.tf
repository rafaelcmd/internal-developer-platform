variable "name" {
  description = "Name of the trail. The bucket policy names the trail by ARN, so changing it re-creates the trail and rewrites the policy."
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket the trail delivers to. S3 bucket names are global, so include the account ID."
  type        = string
}

variable "log_retention_days" {
  description = "Days a delivered log file, and any noncurrent version of it, is kept before S3 expires it"
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days >= 1
    error_message = "log_retention_days must be at least 1."
  }
}

variable "tags" {
  description = "Tags applied to the trail and its bucket"
  type        = map(string)
  default     = {}
}
