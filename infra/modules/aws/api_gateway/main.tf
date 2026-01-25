# =============================================================================
# API GATEWAY REST API
# Main API Gateway configuration using existing OpenAPI specification
# Supports WAFv2, request validation, and VPC Link integration
# =============================================================================

locals {
  openapi_spec_path = "${path.module}/../../../../api/docs/swagger.yaml"

  # API Versioning Configuration
  # This API uses path-based versioning (e.g., /v1/resources)
  # - Current version is defined in var.api_version
  # - Deprecated versions are tracked in var.deprecated_versions
  # - Deprecation headers (RFC 8594) are enabled via var.enable_deprecation_headers
  api_version_path_prefix = "/${var.api_version}"
}

# =============================================================================
# REST API DEFINITION
# Import API from OpenAPI specification with AWS extensions
# =============================================================================

resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = "${var.api_description} (${var.api_version})"

  body = templatefile(local.openapi_spec_path, {
    nlb_uri                = "http://${var.nlb_dns_name}"
    vpc_link_id            = aws_api_gateway_vpc_link.this.id
    cognito_user_pool_arn  = var.cognito_user_pool_arn
    api_version            = var.api_version
    aws_region             = var.aws_region
  })

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  # Fail on warnings during import
  fail_on_warnings = true

  # Minimum compression size (0 = always compress, -1 = never)
  minimum_compression_size = var.minimum_compression_size

  tags = merge(var.tags, {
    Name        = var.api_name
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })
}

# =============================================================================
# VPC LINK CONFIGURATION
# VPC Link for connecting API Gateway REST API to NLB in private subnets
# Note: REST API VPC Links connect directly to NLB (not subnets like HTTP API)
# =============================================================================

resource "aws_api_gateway_vpc_link" "this" {
  name        = var.vpc_link_name
  description = "VPC Link for ${var.api_name}"
  target_arns = [var.nlb_arn]

  tags = merge(var.tags, {
    Name        = var.vpc_link_name
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })
}

# =============================================================================
# API GATEWAY DEPLOYMENT
# Deployment for the REST API
# =============================================================================

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    # Redeploy when OpenAPI spec changes
    redeployment = sha1(templatefile(local.openapi_spec_path, {
      nlb_uri               = "http://${var.nlb_dns_name}"
      vpc_link_id           = aws_api_gateway_vpc_link.this.id
      cognito_user_pool_arn = var.cognito_user_pool_arn
      api_version           = var.api_version
      aws_region            = var.aws_region
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_rest_api.this]
}

# =============================================================================
# API GATEWAY STAGE
# Stage configuration for API deployment with logging and throttling
# =============================================================================

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage_name

  # Enable X-Ray tracing
  xray_tracing_enabled = var.xray_tracing_enabled

  # Access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId         = "$context.requestId"
      extendedRequestId = "$context.extendedRequestId"
      ip                = "$context.identity.sourceIp"
      caller            = "$context.identity.caller"
      user              = "$context.identity.user"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      resourcePath      = "$context.resourcePath"
      status            = "$context.status"
      protocol          = "$context.protocol"
      responseLength    = "$context.responseLength"
      integrationError  = "$context.integrationErrorMessage"
      errorMessage      = "$context.error.message"
      errorType         = "$context.error.responseType"
    })
  }

  # Cache settings (optional)
  cache_cluster_enabled = var.cache_cluster_enabled
  cache_cluster_size    = var.cache_cluster_enabled ? var.cache_cluster_size : null

  tags = merge(var.tags, {
    Name        = "${var.api_name}-${var.stage_name}"
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })

  depends_on = [aws_cloudwatch_log_group.api_gateway_logs]
}

# =============================================================================
# METHOD SETTINGS
# Default method settings for throttling and logging
# =============================================================================

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    # Throttling
    throttling_rate_limit  = var.throttle_rate_limit
    throttling_burst_limit = var.throttle_burst_limit

    # Logging
    logging_level      = var.logging_level
    data_trace_enabled = var.data_trace_enabled
    metrics_enabled    = var.metrics_enabled

    # Caching (per-method override)
    caching_enabled = var.cache_cluster_enabled
  }
}

# =============================================================================
# CLOUDWATCH LOGS
# CloudWatch log group for API Gateway access logs
# =============================================================================

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${var.api_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name        = "/aws/apigateway/${var.api_name}"
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })
}

# =============================================================================
# IAM ROLE FOR CLOUDWATCH LOGGING
# Required for REST API to write to CloudWatch
# =============================================================================

resource "aws_api_gateway_account" "this" {
  count               = var.create_api_gateway_account ? 1 : 0
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch[0].arn

  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch]
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  count = var.create_api_gateway_account ? 1 : 0
  name  = "${var.api_name}-api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.api_name}-api-gateway-cloudwatch-role"
    Project     = var.project
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  count      = var.create_api_gateway_account ? 1 : 0
  role       = aws_iam_role.api_gateway_cloudwatch[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# =============================================================================
# WAF ASSOCIATION
# Associate WAF Web ACL with API Gateway stage for edge protection
# REST APIs support direct WAFv2 association
# =============================================================================

resource "aws_wafv2_web_acl_association" "api_gateway" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = var.waf_web_acl_arn
}

# =============================================================================
# GATEWAY RESPONSES
# Custom error responses for API Gateway errors
# =============================================================================

resource "aws_api_gateway_gateway_response" "unauthorized" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "UNAUTHORIZED"
  status_code   = "401"

  response_templates = {
    "application/json" = jsonencode({
      code      = "UNAUTHORIZED"
      message   = "Missing or invalid authentication token"
      requestId = "$context.requestId"
    })
  }

  response_parameters = {
    "gatewayresponse.header.X-Request-Id"                = "'$context.requestId'"
    "gatewayresponse.header.X-API-Version"               = "'${var.api_version}'"
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "access_denied" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "ACCESS_DENIED"
  status_code   = "403"

  response_templates = {
    "application/json" = jsonencode({
      code      = "ACCESS_DENIED"
      message   = "Access denied"
      requestId = "$context.requestId"
    })
  }

  response_parameters = {
    "gatewayresponse.header.X-Request-Id"                = "'$context.requestId'"
    "gatewayresponse.header.X-API-Version"               = "'${var.api_version}'"
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "bad_request" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "BAD_REQUEST_BODY"
  status_code   = "400"

  response_templates = {
    "application/json" = jsonencode({
      code      = "VALIDATION_ERROR"
      message   = "Request body validation failed"
      requestId = "$context.requestId"
    })
  }

  response_parameters = {
    "gatewayresponse.header.X-Request-Id"                = "'$context.requestId'"
    "gatewayresponse.header.X-API-Version"               = "'${var.api_version}'"
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "throttled" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "THROTTLED"
  status_code   = "429"

  response_templates = {
    "application/json" = jsonencode({
      code      = "RATE_LIMITED"
      message   = "Too many requests. Please retry later."
      requestId = "$context.requestId"
    })
  }

  response_parameters = {
    "gatewayresponse.header.X-Request-Id"                = "'$context.requestId'"
    "gatewayresponse.header.X-API-Version"               = "'${var.api_version}'"
    "gatewayresponse.header.Retry-After"                 = "'60'"
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "internal_error" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "DEFAULT_5XX"
  status_code   = "500"

  response_templates = {
    "application/json" = jsonencode({
      code      = "INTERNAL_ERROR"
      message   = "An internal error occurred"
      requestId = "$context.requestId"
    })
  }

  response_parameters = {
    "gatewayresponse.header.X-Request-Id"                = "'$context.requestId'"
    "gatewayresponse.header.X-API-Version"               = "'${var.api_version}'"
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "waf_blocked" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "WAF_FILTERED"
  status_code   = "403"

  response_templates = {
    "application/json" = jsonencode({
      code      = "WAF_BLOCKED"
      message   = "Request blocked by security rules"
      requestId = "$context.requestId"
    })
  }

  response_parameters = {
    "gatewayresponse.header.X-Request-Id"                = "'$context.requestId'"
    "gatewayresponse.header.X-API-Version"               = "'${var.api_version}'"
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}
