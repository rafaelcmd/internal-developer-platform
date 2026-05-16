# =============================================================================
# GENERAL PROJECT CONFIGURATION
# Core variables that define the project, environment, and AWS configuration
# =============================================================================

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev) used for resource naming and tagging"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
}

variable "service_name" {
  description = "Name of the service being deployed"
  type        = string
}

variable "app_version" {
  description = "Version of the application being deployed"
  type        = string
}

variable "api_version" {
  description = "API version for path-based versioning (e.g., v1, v2)"
  type        = string
  default     = "v1"
}

# =============================================================================
# EKS CONFIGURATION
# Variables for the EKS-on-Fargate cluster that hosts the API and Redis
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes control-plane version"
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API server is reachable from the public internet"
  type        = bool
  default     = true
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "fargate_namespaces" {
  description = "Namespaces routed to Fargate. Pods outside these namespaces won't schedule."
  type        = list(string)
  default     = ["default", "kube-system"]
}

variable "cluster_log_retention_days" {
  description = "CloudWatch retention for EKS control-plane logs"
  type        = number
  default     = 7
}

variable "aws_load_balancer_controller_chart_version" {
  description = "Helm chart version for the AWS Load Balancer Controller"
  type        = string
  default     = "1.8.1"
}

# =============================================================================
# LOAD BALANCER CONFIGURATION
# The NLB itself is provisioned by the AWS Load Balancer Controller from the
# k8s Service in /k8s/api/service.yaml. We only need its name (must match the
# service.beta.kubernetes.io/aws-load-balancer-name annotation) so Terraform
# can look it up via data.aws_lb for the API Gateway VPC Link.
# =============================================================================

variable "nlb_name" {
  description = "Name the AWS Load Balancer Controller assigns to the API NLB. Must match the service.beta.kubernetes.io/aws-load-balancer-name annotation in k8s/api/service.yaml."
  type        = string
}

# =============================================================================
# API GATEWAY CONFIGURATION
# Variables for API Gateway setup and configuration
# =============================================================================

variable "api_gateway_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "api_gateway_description" {
  description = "Description of the API Gateway"
  type        = string
}

variable "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  type        = string
  default     = "dev"
}

variable "api_gateway_auto_deploy" {
  description = "Whether to automatically deploy API changes"
  type        = bool
}

# =============================================================================
# VPC LINK CONFIGURATION
# Variables for API Gateway VPC Link setup
# =============================================================================

variable "vpc_link_name" {
  description = "Name of the VPC Link"
  type        = string
}

# =============================================================================
# API GATEWAY INTEGRATION CONFIGURATION
# Variables for backend integration and timeout settings
# =============================================================================

variable "integration_timeout_ms" {
  description = "Integration timeout in milliseconds"
  type        = number
}

# =============================================================================
# API GATEWAY THROTTLING CONFIGURATION
# Variables for API Gateway throttling and rate limiting
# =============================================================================

variable "throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
}

variable "throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
}

# =============================================================================
# CORS CONFIGURATION
# Variables for Cross-Origin Resource Sharing configuration
# =============================================================================

variable "cors_allow_credentials" {
  description = "Whether to allow credentials in CORS requests"
  type        = bool
}

variable "cors_allow_headers" {
  description = "List of allowed headers for CORS"
  type        = list(string)
}

variable "cors_allow_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
}

variable "cors_allow_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
}

variable "cors_expose_headers" {
  description = "List of headers to expose in CORS responses"
  type        = list(string)
}

variable "cors_max_age" {
  description = "Maximum age for CORS preflight requests in seconds"
  type        = number
}

# =============================================================================
# API GATEWAY LOGGING AND MONITORING CONFIGURATION
# Variables for API Gateway CloudWatch logs and monitoring
# =============================================================================

variable "api_gateway_log_retention_days" {
  description = "CloudWatch log group retention period in days for API Gateway"
  type        = number
}

variable "api_gateway_logging_level" {
  description = "CloudWatch logging level for API Gateway (OFF, ERROR, INFO)"
  type        = string
}

variable "api_gateway_metrics_enabled" {
  description = "Whether to enable CloudWatch metrics for API Gateway"
  type        = bool
}

variable "api_gateway_data_trace_enabled" {
  description = "Whether to enable data trace for API Gateway"
  type        = bool
}

variable "api_gateway_xray_tracing_enabled" {
  description = "Whether to enable X-Ray tracing for API Gateway"
  type        = bool
}

# =============================================================================
# WAF CONFIGURATION
# Variables for AWS WAF Web ACL configuration
# =============================================================================

variable "enable_waf" {
  description = "Whether to enable WAF protection for the API Gateway"
  type        = bool
  default     = true
}

variable "waf_rate_limit_requests" {
  description = "Maximum number of requests per 5-minute period per IP"
  type        = number
  default     = 2000
}

variable "waf_max_request_body_size" {
  description = "Maximum request body size in bytes"
  type        = number
  default     = 10240
}

variable "waf_common_rules_excluded" {
  description = "List of AWS Common Rule Set rules to exclude"
  type        = list(string)
  default     = []
}

variable "waf_enable_logging" {
  description = "Enable CloudWatch logging for WAF"
  type        = bool
  default     = true
}

variable "waf_log_retention_days" {
  description = "Number of days to retain WAF logs"
  type        = number
  default     = 7
}

# =============================================================================
# LAMBDA CONFIGURATION
# Variables for Lambda function (Datadog forwarder) configuration
# =============================================================================

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
}

# Archive Configuration
variable "archive_type" {
  description = "Type of archive to create for Lambda deployment package"
  type        = string
}

variable "archive_output_path_prefix" {
  description = "Prefix for the archive output path"
  type        = string
}

# IAM Configuration
variable "iam_role_name_suffix" {
  description = "Suffix for the IAM role name"
  type        = string
}

variable "assume_role_policy" {
  description = "IAM assume role policy document"
  type = object({
    Version = string
    Statement = list(object({
      Action = string
      Effect = string
      Principal = object({
        Service = string
      })
    }))
  })
  default = {
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  }
}

variable "lambda_basic_execution_policy_arn" {
  description = "ARN of the AWS Lambda basic execution policy"
  type        = string
}

variable "additional_policy_name_suffix" {
  description = "Suffix for the additional IAM policy name"
  type        = string
}

# Lambda Permission Configuration
variable "permission_statement_id" {
  description = "Statement ID for the Lambda permission"
  type        = string
}

variable "permission_action" {
  description = "Action for the Lambda permission"
  type        = string
}

variable "permission_principal" {
  description = "Principal for the Lambda permission"
  type        = string
}

# CloudWatch Logs Configuration
variable "log_group_name_prefix" {
  description = "Prefix for the CloudWatch log group name"
  type        = string
}

# =============================================================================
# SQS CONFIGURATION
# Variables for SQS queue configuration
# =============================================================================

variable "queue_name" {
  description = "Name of the SQS queue"
  type        = string
}

variable "delay_seconds" {
  description = "The time in seconds that the delivery of all messages in the queue will be delayed"
  type        = number
}

variable "max_message_size" {
  description = "The limit of how many bytes a message can contain before Amazon SQS rejects it"
  type        = number
}

variable "message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message"
  type        = number
}

variable "receive_wait_time_seconds" {
  description = "The time for which a ReceiveMessage call will wait for a message to arrive"
  type        = number
}

variable "ssm_parameter_name" {
  description = "Name of the SSM parameter for storing the queue URL"
  type        = string
}

variable "ssm_parameter_type" {
  description = "Type of the SSM parameter"
  type        = string
}

# =============================================================================
# REDIS CONFIGURATION
# Redis runs as a k8s Deployment (see /k8s/redis/). We only need to publish the
# in-cluster DNS endpoint to SSM so the API can resolve it at runtime — same
# contract the ECS-era module exposed.
# =============================================================================

variable "redis_ssm_parameter_name" {
  description = "SSM parameter name where the Redis host:port endpoint is published"
  type        = string
}

variable "redis_endpoint" {
  description = "host:port the API uses to reach Redis. Defaults to the Service DNS name created by /k8s/redis/service.yaml."
  type        = string
  default     = "redis.default.svc.cluster.local:6379"
}
