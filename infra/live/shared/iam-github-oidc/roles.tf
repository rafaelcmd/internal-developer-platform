# Per-component pipeline roles.
#
# Each Terraform component assumes a role scoped to the services that
# component provisions, so a compromised or misbehaving run is bounded by
# the stack it belongs to rather than the account. Role names follow
# github-actions-tf-<component>; the workflows build the ARN from that
# convention plus the AWS_ACCOUNT_ID repo variable, so adding a component
# needs no new repo configuration.
#
# Every trust policy pins the repository by its immutable numeric IDs and the
# workflow file by job_workflow_ref, so a role is assumable only from the
# workflow written for it, on main. The sub claims match the identities a
# pipeline job presents: the main branch ref for ungated jobs, and one entry
# per environment the gated apply/destroy jobs can run in: `dev` normally, and
# `dev-auto` when the DISABLE_DEPLOYMENT_APPROVALS repository variable is set
# (see .github/workflows/_terraform.yml). A job that names an environment
# presents `environment:<name>` as its subject instead of the ref, so an
# environment missing from this list fails AssumeRoleWithWebIdentity.
# Pull-request plans use the separate read-only role in plan_role.tf.

locals {
  github_trust_base = {
    "token.actions.githubusercontent.com:aud"                 = ["sts.amazonaws.com"]
    "token.actions.githubusercontent.com:repository_id"       = [var.github_repository_id]
    "token.actions.githubusercontent.com:repository_owner_id" = [var.github_repository_owner_id]
  }

  main_branch_sub = "repo:${var.github_repository}:ref:refs/heads/main"

  pipeline_trust_subs = [
    local.main_branch_sub,
    "repo:${var.github_repository}:environment:dev",
    "repo:${var.github_repository}:environment:dev-auto"
  ]

  # _terraform.yml is a reusable workflow, so this is the claim every Terraform
  # job presents, whichever caller (cd-infra-apply, ops-*) started the run.
  terraform_workflow_ref = "${var.github_repository}/.github/workflows/_terraform.yml@refs/heads/main"

  component_policy_arns = {
    vpc                = [aws_iam_policy.pipeline_vpc.arn]
    ecr                = [aws_iam_policy.pipeline_ecr.arn]
    datadog            = [aws_iam_policy.pipeline_datadog.arn]
    identity           = [aws_iam_policy.pipeline_identity.arn]
    api                = [aws_iam_policy.pipeline_api.arn, aws_iam_policy.pipeline_api_iam.arn]
    provisioner        = [aws_iam_policy.pipeline_provisioner.arn]
    "api-gateway"      = [aws_iam_policy.pipeline_api_gateway.arn]
    scaffolder         = [aws_iam_policy.pipeline_scaffolder.arn]
    "infra-worker-aws" = [aws_iam_policy.pipeline_infra_worker_aws.arn]
  }
}

module "component_roles" {
  for_each = local.component_policy_arns

  source            = "../../../modules/aws/oidc_role"
  role_name         = "github-actions-tf-${each.key}"
  oidc_provider_arn = module.github_actions_oidc.oidc_provider_arn

  string_equals = merge(local.github_trust_base, {
    "token.actions.githubusercontent.com:sub"              = local.pipeline_trust_subs
    "token.actions.githubusercontent.com:job_workflow_ref" = [local.terraform_workflow_ref]
  })

  policy_arns = concat([aws_iam_policy.pipeline_common.arn], each.value)

  tags = local.tags
}

module "deploy_role" {
  source            = "../../../modules/aws/oidc_role"
  role_name         = "github-actions-deploy"
  oidc_provider_arn = module.github_actions_oidc.oidc_provider_arn

  # Deploy jobs name no environment, so only the branch subject applies. The
  # cd-*.yml wildcard is the one StringLike: each deploy workflow is its own
  # file, and a new one should not need a trust change.
  string_equals = merge(local.github_trust_base, {
    "token.actions.githubusercontent.com:sub" = [local.main_branch_sub]
  })
  string_like = {
    "token.actions.githubusercontent.com:job_workflow_ref" = ["${var.github_repository}/.github/workflows/cd-*.yml@refs/heads/main"]
  }

  policy_arns = [aws_iam_policy.pipeline_deploy.arn]

  tags = local.tags
}
