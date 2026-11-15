# Read-only role for pull-request plan runs.
#
# GitHub issues PR-triggered OIDC tokens with the subject
# `repo:<org>/<repo>:pull_request`, which the component roles' trust policies,
# accepting only main-branch refs, reject. That is deliberate: unmerged code
# must never hold write-capable credentials. Pull-request plans assume this role
# instead, and the workflow selects it via the AWS_PLAN_ROLE_ARN repo variable,
# which must hold the `github_actions_plan_role_arn` output of this stack.
#
# Plain resources rather than modules/aws/oidc_role, because its managed policy
# is AWS's ReadOnlyAccess rather than one of this stack's pipeline policies.

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
          StringEquals = merge(local.github_trust_base, {
            "token.actions.githubusercontent.com:sub" = ["repo:${var.github_repository}:pull_request"]
          })
          # A pull request's ref is refs/pull/<number>/merge, so the workflow
          # file is pinned and the ref is not.
          StringLike = {
            "token.actions.githubusercontent.com:job_workflow_ref" = ["${var.github_repository}/.github/workflows/_terraform.yml@refs/pull/*"]
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

# ReadOnlyAccess also reads data: table items, objects, log events, queue
# messages and user records. A plan only needs configuration, and this role runs
# unmerged code, so those reads are denied outright.
resource "aws_iam_role_policy" "github_actions_plan_deny_data_reads" {
  name = "deny-data-reads"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDataReads"
        Effect = "Deny"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:ListUsers",
          "cognito-idp:ListUsersInGroup",
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:GetRecords",
          "dynamodb:Query",
          "dynamodb:Scan",
          "logs:FilterLogEvents",
          "logs:GetLogEvents",
          "logs:GetQueryResults",
          "logs:StartLiveTail",
          "logs:StartQuery",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "secretsmanager:GetSecretValue",
          "sqs:ReceiveMessage",
          "states:GetExecutionHistory"
        ]
        Resource = "*"
      },
      # The api plan reads the Datadog API key, a SecureString, through the
      # aws_ssm_parameter data source, so decryption through SSM stays allowed.
      # Any other use of a key is denied.
      {
        Sid      = "DenyDecryptOutsideSSM"
        Effect   = "Deny"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringNotLike = {
            "kms:ViaService" = "ssm.*.amazonaws.com"
          }
        }
      }
    ]
  })
}
