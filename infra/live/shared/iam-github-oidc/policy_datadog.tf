# CI role for the datadog component (live/shared/datadog).
# Most of this stack talks to Datadog's API rather than AWS. Its AWS footprint
# is the integration role Datadog assumes to pull metrics. The pipeline manages
# that one role by name and may attach only two policies to it: AWS's
# SecurityAudit and the Datadog policy this bootstrap stack owns
# (datadog_integration_policy.tf). It cannot write the role's permissions
# itself, which, combined with control of its trust, would let it hand any
# account any permission here.

resource "aws_iam_policy" "pipeline_datadog" {
  name        = "${var.project}-${var.environment}-pipeline-datadog-policy"
  description = "Pipeline policy for the datadog stack (AWS integration role)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IntegrationRoleLifecycle"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = local.datadog_role_arn
      },
      {
        Sid    = "IntegrationRoleApprovedPoliciesOnly"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = local.datadog_role_arn
        Condition = {
          ArnEquals = {
            "iam:PolicyARN" = [
              "arn:aws:iam::aws:policy/SecurityAudit",
              aws_iam_policy.datadog_integration.arn
            ]
          }
        }
      },
      # Deleting an inline policy can only narrow the role, so it is granted
      # without the attach restriction above. Writing one is not granted at all.
      {
        Sid      = "IntegrationRoleRemoveInlinePolicy"
        Effect   = "Allow"
        Action   = "iam:DeleteRolePolicy"
        Resource = local.datadog_role_arn
      }
    ]
  })

  tags = local.tags
}

locals {
  datadog_role_arn = "arn:aws:iam::${local.account_id}:role/${var.datadog_role_name}"
}
