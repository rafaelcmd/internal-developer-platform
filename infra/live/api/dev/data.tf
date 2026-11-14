# Everything this stack needs from its siblings, read from SSM Parameter Store
# rather than from their state. There are no terraform_remote_state reads
# anywhere in live/: a consumer needs IAM read on a known path and nothing more,
# so stacks can be applied and destroyed independently.

# Published by shared/vpc.
data "aws_ssm_parameter" "vpc_id" {
  name = "/idp/shared/vpc/id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/idp/shared/vpc/private_subnet_ids"
}

# Published by shared/datadog. Passed to the cluster's Datadog Cluster Agent
# and to the OTel Collector's exporter.
data "aws_ssm_parameter" "datadog_api_key" {
  name            = "/${var.project}/${var.environment}/datadog/api_key"
  with_decryption = true
}

# Published by shared/identity. Scoped into the API's IRSA policy in irsa.tf so
# the pod can call cognito-idp for signup and login.
data "aws_ssm_parameter" "cognito_user_pool_arn" {
  name = "/idp/shared/identity/user_pool_arn"
}

# Published by shared/iam-github-oidc. Every role this stack creates carries it:
# the pipeline is allowed to create and change roles only with this boundary
# attached. See docs/adr/0009.
data "aws_ssm_parameter" "workload_boundary_arn" {
  name = "/idp/shared/iam/workload_boundary_arn"
}
