# The trust anchor for CI. GitHub Actions jobs exchange an OIDC token for
# temporary AWS credentials here, which is why no AWS access key exists in any
# repository secret.
#
# This is a bootstrap stack: every other stack's pipeline depends on it, so it
# is applied by hand and is deliberately not part of the orchestrator chain.
#
# This file creates the OIDC provider itself, which an account holds exactly one
# of per issuer. The roles that use it are in roles.tf (one per Terraform
# component, plus the deploy role) and plan_role.tf (read-only, for pull
# requests), with their permissions split across the policy_*.tf files. The
# guardrails every pipeline role shares are in policy_common.tf and boundary.tf.
# See docs/adr/0009 for how paths and the boundary bound what a pipeline can do.

data "aws_caller_identity" "current" {}

data "tls_certificate" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"
}

module "github_actions_oidc" {
  source         = "../../../modules/aws/oidc"
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint     = data.tls_certificate.github_oidc.certificates[0].sha1_fingerprint
  tags           = local.tags
}
