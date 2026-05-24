# =============================================================================
# DATA SOURCES
# Cross-workspace values are sourced from SSM Parameter Store (published by the
# producer stacks). This decouples workspaces — no terraform_remote_state reads
# means a consumer never needs TFC access to a producer's state.
# =============================================================================

# Shared VPC — published by the shared/vpc workspace
data "aws_ssm_parameter" "vpc_id" {
  name = "/idp/shared/vpc/id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/idp/shared/vpc/private_subnet_ids"
}

# Datadog API Key (already in SSM, owned outside this stack)
data "aws_ssm_parameter" "datadog_api_key" {
  name            = "/${var.project}/${var.environment}/datadog/api_key"
  with_decryption = true
}
