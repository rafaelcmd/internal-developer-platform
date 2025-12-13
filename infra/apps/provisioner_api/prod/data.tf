# =============================================================================
# DATA SOURCES
# Remote state data sources for retrieving outputs from other Terraform workspaces
# =============================================================================

# Shared VPC infrastructure
data "terraform_remote_state" "shared_vpc" {
  backend = "remote"
  config = {
    organization = "cloudops-manager-org"
    workspaces = {
      name = "cloudops-shared-vpc"
    }
  }
}

# ECR repository for application images
data "terraform_remote_state" "cloudops_manager_ecr_repository" {
  backend = "remote"
  config = {
    organization = "cloudops-manager-org"
    workspaces = {
      name = "cloudops-shared-ecr"
    }
  }
}
