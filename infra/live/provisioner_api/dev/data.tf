# =============================================================================
# DATA SOURCES
# Remote state data sources for retrieving outputs from other Terraform workspaces
# =============================================================================

# Shared VPC infrastructure
data "terraform_remote_state" "shared_vpc" {
  backend = "remote"
  config = {
    organization = "internal-developer-platform-org"
    workspaces = {
      name = "internal-developer-platform-shared-vpc"
    }
  }
}

# ECR repository for application images
data "terraform_remote_state" "internal_developer_platform_ecr_repository" {
  backend = "remote"
  config = {
    organization = "internal-developer-platform-org"
    workspaces = {
      name = "internal-developer-platform-shared-ecr"
    }
  }
}

# Datadog API Key from SSM
data "aws_ssm_parameter" "datadog_api_key" {
  name            = "/${var.project}/${var.environment}/datadog/api_key"
  with_decryption = true
}

# Cognito user pool (created in the api_gateway workspace) — needed so the API
# IRSA role can be scoped to the actual user pool ARN.
data "terraform_remote_state" "provisioner_api_gateway" {
  backend = "remote"
  config = {
    organization = "internal-developer-platform-org"
    workspaces = {
      name = "internal-developer-platform-provisioner-api-gateway-dev"
    }
  }
}
