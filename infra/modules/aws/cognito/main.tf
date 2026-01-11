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

resource "aws_ssm_parameter" "cognito_client_id" {
  name  = "/INTERNAL_DEVELOPER_PLATFORM/COGNITO_CLIENT_ID"
  type  = "String"
  value = aws_cognito_user_pool_client.this.id

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
  })
}
