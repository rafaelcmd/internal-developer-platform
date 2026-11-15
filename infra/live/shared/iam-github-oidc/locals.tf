locals {
  tags = {
    Environment = var.environment
    Project     = var.project
  }

  account_id = data.aws_caller_identity.current.account_id

  # Workload roles live under /idp/workload/<component>/, one path per pipeline,
  # and each pipeline's IAM grants reach only its own path. Boundaries and the
  # policies only this stack may change have paths of their own, outside every
  # pipeline grant.
  workload_path_prefix    = "/idp/workload/"
  boundary_path           = "/idp/boundary/"
  integration_policy_path = "/idp/integration/"

  # Every SSM prefix the platform's stacks publish under, and so every
  # parameter a pipeline reads.
  project_parameter_arns = [
    "arn:aws:ssm:*:${local.account_id}:parameter/idp/*",
    "arn:aws:ssm:*:${local.account_id}:parameter/INTERNAL_DEVELOPER_PLATFORM/*",
    "arn:aws:ssm:*:${local.account_id}:parameter/${var.project}/*"
  ]

  # Claims every GitHub OIDC trust in this stack pins. The numeric repository
  # IDs survive a rename and are not reused by a re-created repository. Each
  # role adds its own subject and workflow claims (roles.tf, plan_role.tf).
  github_trust_base = {
    "token.actions.githubusercontent.com:aud"                 = ["sts.amazonaws.com"]
    "token.actions.githubusercontent.com:repository_id"       = [var.github_repository_id]
    "token.actions.githubusercontent.com:repository_owner_id" = [var.github_repository_owner_id]
  }
}
