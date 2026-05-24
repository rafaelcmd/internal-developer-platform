module "cognito" {
  source = "../../../modules/aws/cognito"

  user_pool_name = var.user_pool_name
  project        = var.project
  environment    = var.environment

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Workspace   = "shared/identity"
  }
}
