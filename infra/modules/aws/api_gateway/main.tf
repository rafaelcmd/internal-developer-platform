# =============================================================================
# API GATEWAY HTTP API
# Main API Gateway configuration using existing OpenAPI specification
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

resource "aws_apigatewayv2_api" "this" {
  name          = var.api_name
  description   = "${var.api_description} (${var.api_version})"
  protocol_type = "HTTP"

  body = templatefile(local.openapi_spec_path, {
    nlb_listener_arn = var.nlb_listener_arn
    vpc_link_id      = aws_apigatewayv2_vpc_link.this.id
    jwt_issuer       = var.jwt_issuer
    jwt_audience     = jsonencode(var.jwt_audience)
    api_version      = var.api_version
  })

  fail_on_warnings = true

  cors_configuration {
    allow_credentials = var.cors_allow_credentials
    allow_headers     = var.cors_allow_headers
    allow_methods     = var.cors_allow_methods
    allow_origins     = var.cors_allow_origins
    expose_headers    = var.cors_expose_headers
    max_age           = var.cors_max_age
  }

  tags = merge(var.tags, {
    Name        = var.api_name
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })
}

resource "aws_apigatewayv2_deployment" "this" {
  api_id = aws_apigatewayv2_api.this.id

  triggers = {
    redeploy_hash = sha1(templatefile(local.openapi_spec_path, {
      nlb_listener_arn = var.nlb_listener_arn
      vpc_link_id      = aws_apigatewayv2_vpc_link.this.id
      jwt_issuer       = var.jwt_issuer
      jwt_audience     = jsonencode(var.jwt_audience)
      api_version      = var.api_version
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_apigatewayv2_api.this]
}

# =============================================================================
# VPC LINK CONFIGURATION
# VPC Link for connecting API Gateway to NLB in private subnets
# =============================================================================

# Security group for VPC Link (optional for NLB but recommended for network isolation)
resource "aws_security_group" "vpc_link" {
  count  = length(var.vpc_link_security_group_ids) == 0 ? 1 : 0
  name   = "${var.vpc_link_name}-sg"
  vpc_id = var.vpc_id

  # Allow outbound traffic to NLB port
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(var.tags, {
    Name        = "${var.vpc_link_name}-sg"
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = var.vpc_link_name
  security_group_ids = length(var.vpc_link_security_group_ids) > 0 ? var.vpc_link_security_group_ids : [aws_security_group.vpc_link[0].id]
  subnet_ids         = var.vpc_link_subnet_ids

  tags = merge(var.tags, {
    Name        = var.vpc_link_name
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })
}

# =============================================================================
# API GATEWAY STAGE
# Stage configuration for API deployment
# =============================================================================

resource "aws_apigatewayv2_stage" "this" {
  api_id        = aws_apigatewayv2_api.this.id
  name          = var.stage_name
  auto_deploy   = var.auto_deploy
  deployment_id = var.auto_deploy ? null : aws_apigatewayv2_deployment.this.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
      errorType      = "$context.error.messageString"
    })
  }

  default_route_settings {
    throttling_rate_limit  = var.throttle_rate_limit
    throttling_burst_limit = var.throttle_burst_limit
  }

  tags = merge(var.tags, {
    Name        = "${var.api_name}-${var.stage_name}"
    Project     = var.project
    Environment = var.environment
    ApiVersion  = var.api_version
  })
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
# WAF ASSOCIATION
# Associate WAF Web ACL with API Gateway stage for edge validation
# =============================================================================

resource "aws_wafv2_web_acl_association" "api_gateway" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_apigatewayv2_stage.this.arn
  web_acl_arn  = var.waf_web_acl_arn
}
