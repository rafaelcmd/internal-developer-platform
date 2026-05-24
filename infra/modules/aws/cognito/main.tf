resource "aws_cognito_user_pool" "this" {
  name = var.user_pool_name

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Account Confirmation"
    email_message        = "Your confirmation code is {####}"
  }

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
  })
}

resource "aws_cognito_user_pool_client" "this" {
  name = "${var.user_pool_name}-client"

  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
}

locals {
  cognito_common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
  })
}

# Legacy path consumed by the Go API runtime (see application.go).
resource "aws_ssm_parameter" "cognito_client_id_legacy" {
  name  = "/INTERNAL_DEVELOPER_PLATFORM/COGNITO_CLIENT_ID"
  type  = "String"
  value = aws_cognito_user_pool_client.this.id

  tags = local.cognito_common_tags
}

# Normalized identity parameters consumed by sibling Terraform stacks (gateway
# authorizer, API IRSA scope). Centralizing under /idp/shared/identity/* makes
# the cross-stack contract explicit and decouples consumers from the producer
# workspace.
resource "aws_ssm_parameter" "user_pool_id" {
  name  = "/idp/shared/identity/user_pool_id"
  type  = "String"
  value = aws_cognito_user_pool.this.id

  tags = local.cognito_common_tags
}

resource "aws_ssm_parameter" "user_pool_arn" {
  name  = "/idp/shared/identity/user_pool_arn"
  type  = "String"
  value = aws_cognito_user_pool.this.arn

  tags = local.cognito_common_tags
}

resource "aws_ssm_parameter" "user_pool_client_id" {
  name  = "/idp/shared/identity/user_pool_client_id"
  type  = "String"
  value = aws_cognito_user_pool_client.this.id

  tags = local.cognito_common_tags
}
