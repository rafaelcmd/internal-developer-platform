module "eks" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/eks?ref=main"

  # Infrastructure dependencies
  vpc_id             = data.terraform_remote_state.shared_vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.shared_vpc.outputs.private_subnet_ids

  # Project / region
  aws_region  = var.aws_region
  environment = var.environment
  project     = var.project

  # Cluster
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Endpoint access
  endpoint_public_access  = var.cluster_endpoint_public_access
  endpoint_private_access = true
  public_access_cidrs     = var.cluster_public_access_cidrs

  # Pods schedule onto Fargate. The API and Redis live in `default`;
  # kube-system is included so CoreDNS / the LB controller schedule.
  fargate_namespaces = var.fargate_namespaces

  # Control plane logs
  log_retention_days = var.cluster_log_retention_days

  # AWS Load Balancer Controller (provisions the NLB for the API Service)
  install_aws_load_balancer_controller       = true
  aws_load_balancer_controller_chart_version = var.aws_load_balancer_controller_chart_version

  tags = local.tags
}

# The API is exposed as a k8s Service of type=LoadBalancer (see /k8s/api/service.yaml),
# which the AWS Load Balancer Controller backs with an NLB. The NLB has to exist
# before the API Gateway VPC Link can target it, so we read it back by tag.
# Required tagging on the Service (set in the manifest):
#   service.beta.kubernetes.io/aws-load-balancer-name: ${nlb_name}
data "aws_lb" "api" {
  name = var.nlb_name

  depends_on = [module.eks]
}

module "sqs" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/sqs?ref=main"

  # SQS configuration
  queue_name                = var.queue_name
  delay_seconds             = var.delay_seconds
  max_message_size          = var.max_message_size
  message_retention_seconds = var.message_retention_seconds
  receive_wait_time_seconds = var.receive_wait_time_seconds

  # SSM parameter configuration
  ssm_parameter_name = var.ssm_parameter_name
  ssm_parameter_type = var.ssm_parameter_type

  # Common configuration
  project     = var.project
  environment = var.environment

  # Common tags
  tags = local.tags
}

# =============================================================================
# REDIS ENDPOINT SSM PARAMETER
# Redis itself runs as an in-cluster k8s Deployment (see /k8s/redis/), reachable
# via cluster DNS. Publishing the endpoint to SSM keeps the API's runtime config
# identical to the ECS-era contract.
# =============================================================================

resource "aws_ssm_parameter" "redis_endpoint" {
  name  = var.redis_ssm_parameter_name
  type  = "String"
  value = var.redis_endpoint

  tags = local.tags
}

# Datadog Lambda Forwarder for collecting application logs (CloudWatch -> Datadog).
# Application logs now originate from the CloudWatch log group the Datadog agent
# DaemonSet writes to, or from EKS control-plane logs.
module "datadog_forwarder" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/lambda?ref=main"

  # Basic Lambda configuration
  function_name                  = var.lambda_function_name
  source_dir                     = "${path.module}/lambda-src"
  handler                        = "lambda_function.lambda_handler"
  runtime                        = var.lambda_runtime
  timeout                        = var.lambda_timeout
  memory_size                    = var.lambda_memory_size
  reserved_concurrent_executions = -1
  log_retention_days             = 7

  # Archive configuration
  archive_type               = var.archive_type
  archive_output_path_prefix = var.archive_output_path_prefix

  # IAM configuration
  iam_role_name_suffix              = var.iam_role_name_suffix
  assume_role_policy                = var.assume_role_policy
  lambda_basic_execution_policy_arn = var.lambda_basic_execution_policy_arn
  additional_policy_name_suffix     = var.additional_policy_name_suffix

  # Lambda permission configuration
  allow_cloudwatch_logs_invocation = true
  permission_statement_id          = var.permission_statement_id
  permission_action                = var.permission_action
  permission_principal             = var.permission_principal

  # CloudWatch logs configuration
  log_group_name_prefix = var.log_group_name_prefix

  # Environment variables
  environment_variables = {
    DD_API_KEY = data.aws_ssm_parameter.datadog_api_key.value
    DD_SITE    = "datadoghq.com"
    DD_SOURCE  = "aws"
    DD_TAGS    = "env:${var.environment},project:${var.project},service:${var.service_name}"
  }

  # Tags
  tags        = local.tags
  project     = var.project
  environment = var.environment

  # Additional IAM policy for Datadog forwarder
  additional_inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::*/*",
          "arn:aws:s3:::*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

module "api_gateway" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/api_gateway?ref=main"

  # API Gateway configuration
  api_name        = var.api_gateway_name
  api_description = var.api_gateway_description
  aws_region      = var.aws_region

  # VPC Link configuration (REST API uses NLB ARN directly).
  # The NLB is provisioned by the AWS Load Balancer Controller from the
  # k8s Service in /k8s/api/service.yaml; we read it back via data.aws_lb.api.
  vpc_link_name = var.vpc_link_name
  nlb_arn       = data.aws_lb.api.arn
  nlb_dns_name  = data.aws_lb.api.dns_name

  # Cognito authorizer configuration (REST API uses User Pool ARN)
  cognito_user_pool_arn = module.cognito.user_pool_arn

  # Stage configuration
  stage_name = var.api_gateway_stage_name

  # API versioning
  api_version = var.api_version

  # Endpoint configuration (REST API specific)
  endpoint_type            = "REGIONAL"
  minimum_compression_size = -1

  # Throttling configuration
  throttle_rate_limit  = var.throttle_rate_limit
  throttle_burst_limit = var.throttle_burst_limit

  # Logging and monitoring configuration
  log_retention_days         = var.api_gateway_log_retention_days
  logging_level              = var.api_gateway_logging_level
  data_trace_enabled         = var.api_gateway_data_trace_enabled
  metrics_enabled            = var.api_gateway_metrics_enabled
  xray_tracing_enabled       = var.api_gateway_xray_tracing_enabled
  create_api_gateway_account = true

  # Caching (disabled by default)
  cache_cluster_enabled = false

  # WAF configuration (REST API supports direct WAF association)
  enable_waf      = var.enable_waf
  waf_web_acl_arn = var.enable_waf ? module.waf.web_acl_arn : null

  # Common configuration
  project     = var.project
  environment = var.environment

  tags = local.tags
}

# =============================================================================
# WAF MODULE
# AWS WAF Web ACL for API Gateway edge protection
# =============================================================================

module "waf" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/waf?ref=main"

  web_acl_name        = "${var.project}-${var.environment}-api-waf"
  web_acl_description = "WAF Web ACL for ${var.project} API Gateway"

  # Rate limiting
  rate_limit_requests = var.waf_rate_limit_requests

  # Request size validation
  max_request_body_size = var.waf_max_request_body_size

  # Rule exclusions (if any rules cause false positives)
  common_rules_excluded = var.waf_common_rules_excluded

  # Logging
  enable_logging     = var.waf_enable_logging
  log_retention_days = var.waf_log_retention_days

  # Common configuration
  project     = var.project
  environment = var.environment
  tags        = local.tags
}

module "cognito" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/cognito?ref=main"

  user_pool_name = "${var.project}-${var.environment}-user-pool"
  project        = var.project
  environment    = var.environment
  tags           = local.tags
}
