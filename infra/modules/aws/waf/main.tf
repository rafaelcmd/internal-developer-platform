# =============================================================================
# AWS WAF WEB ACL
# Web Application Firewall for API Gateway edge protection
# Implements DVA-C02 best practice: "Validate at the edge"
# =============================================================================

resource "aws_wafv2_web_acl" "api" {
  name        = var.web_acl_name
  description = var.web_acl_description
  scope       = "REGIONAL" # Required for API Gateway

  default_action {
    allow {}
  }

  # =============================================================================
  # RULE 1: AWS Managed Rules - Common Rule Set
  # Protects against common web exploits (SQLi, XSS, etc.)
  # =============================================================================
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        # Exclude rules that might cause false positives for API use cases
        dynamic "rule_action_override" {
          for_each = var.common_rules_excluded
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.web_acl_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # =============================================================================
  # RULE 2: AWS Managed Rules - Known Bad Inputs
  # Blocks requests with known malicious patterns
  # =============================================================================
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.web_acl_name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # =============================================================================
  # RULE 3: Rate Limiting
  # Prevents abuse by limiting requests per IP
  # =============================================================================
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {
        custom_response {
          response_code = 429
          custom_response_body_key = "rate-limited"
        }
      }
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_requests
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.web_acl_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # =============================================================================
  # RULE 4: Request Size Constraints
  # Validates request body size at the edge
  # =============================================================================
  rule {
    name     = "RequestSizeConstraint"
    priority = 4

    action {
      block {
        custom_response {
          response_code = 413
          custom_response_body_key = "request-too-large"
        }
      }
    }

    statement {
      size_constraint_statement {
        field_to_match {
          body {
            oversize_handling = "MATCH"
          }
        }
        comparison_operator = "GT"
        size                = var.max_request_body_size
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.web_acl_name}-size-constraint"
      sampled_requests_enabled   = true
    }
  }

  # =============================================================================
  # RULE 5: SQL Injection Protection
  # AWS Managed Rule for SQL injection protection
  # =============================================================================
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.web_acl_name}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # =============================================================================
  # CUSTOM RESPONSE BODIES
  # Standardized error responses for WAF blocks
  # =============================================================================
  custom_response_body {
    key          = "rate-limited"
    content      = jsonencode({
      code      = "RATE_LIMITED"
      message   = "Too many requests. Please try again later."
    })
    content_type = "APPLICATION_JSON"
  }

  custom_response_body {
    key          = "request-too-large"
    content      = jsonencode({
      code      = "REQUEST_TOO_LARGE"
      message   = "Request body exceeds maximum allowed size."
    })
    content_type = "APPLICATION_JSON"
  }

  custom_response_body {
    key          = "blocked"
    content      = jsonencode({
      code      = "BLOCKED"
      message   = "Request blocked by security policy."
    })
    content_type = "APPLICATION_JSON"
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.web_acl_name
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name        = var.web_acl_name
    Project     = var.project
    Environment = var.environment
  })
}

# =============================================================================
# CLOUDWATCH LOG GROUP FOR WAF
# Logging for WAF requests (required prefix: aws-waf-logs-)
# =============================================================================

resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_logging ? 1 : 0

  name              = "aws-waf-logs-${var.web_acl_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name        = "aws-waf-logs-${var.web_acl_name}"
    Project     = var.project
    Environment = var.environment
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "waf" {
  count = var.enable_logging ? 1 : 0

  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.api.arn

  # Only log blocked requests to reduce costs
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}
