module "cognito" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/cognito?ref=main"

  user_pool_name = "${var.project}-${var.environment}-user-pool"
  project        = var.project
  environment    = var.environment
  tags           = local.tags
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
