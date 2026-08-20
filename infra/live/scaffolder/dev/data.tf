# =============================================================================
# DATA SOURCES
# Cross-workspace values are sourced from SSM Parameter Store (published by the
# producer stacks). This decouples workspaces — no terraform_remote_state reads
# means a consumer never needs TFC access to a producer's state.
# =============================================================================

data "aws_caller_identity" "current" {}

# EKS cluster coordinates — published by the `api` component, which owns the
# cluster (infra/live/provisioner_api/dev/eks_ssm.tf).
data "aws_ssm_parameter" "eks_cluster_name" {
  name = "/idp/shared/eks/cluster_name"
}

data "aws_ssm_parameter" "eks_cluster_endpoint" {
  name = "/idp/shared/eks/cluster_endpoint"
}

data "aws_ssm_parameter" "eks_cluster_ca" {
  name = "/idp/shared/eks/cluster_certificate_authority_data"
}

data "aws_ssm_parameter" "eks_oidc_provider_arn" {
  name = "/idp/shared/eks/oidc_provider_arn"
}

data "aws_ssm_parameter" "eks_oidc_provider_url" {
  name = "/idp/shared/eks/oidc_provider_url"
}
