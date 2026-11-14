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
}
