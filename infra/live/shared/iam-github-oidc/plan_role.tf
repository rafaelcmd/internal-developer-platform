# Read-only role for pull-request plan runs.
#
# GitHub issues PR-triggered OIDC tokens with the subject
# `repo:<org>/<repo>:pull_request`, which the main role's trust policy
# (main-branch refs only) rejects — deliberately: unmerged code must never
# hold write-capable credentials. PR plans assume this role instead; the
# workflow selects it via the AWS_PLAN_ROLE_ARN repo variable, which must
# hold the `github_actions_plan_role_arn` output of this stack.
#
# Plain resources rather than a second oidc module instance: the module also
# creates the OIDC provider, which must exist exactly once per account, so
# this role reuses the provider from module.github_actions_oidc.

resource "aws_iam_role" "github_actions_plan" {
  name = "github-actions-oidc-plan-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = module.github_actions_oidc.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:rafaelcmd/internal-developer-platform:pull_request"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# ReadOnlyAccess suffices for `terraform plan`: state refresh only describes
# resources. State itself lives in Terraform Cloud, reached via TF_API_TOKEN,
# not AWS.
resource "aws_iam_role_policy_attachment" "github_actions_plan_readonly" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
