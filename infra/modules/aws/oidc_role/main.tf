# An IAM role assumable through an OIDC provider that already exists.
#
# The provider itself comes from modules/aws/oidc, which an account holds once
# per issuer URL; every role attaches to it. This is what gives each Terraform
# component its own github-actions-tf-<component> role instead of one shared
# role across every stack. The trust conditions are the security boundary: they
# decide which repository, workflow, branch and environment may assume the role.

locals {
  # IAM rejects a condition operator with no keys, so an operator the caller
  # left empty is dropped rather than rendered as {}.
  trust_conditions = {
    for operator, keys in {
      StringEquals = var.string_equals
      StringLike   = var.string_like
    } : operator => keys if length(keys) > 0
  }
}

resource "aws_iam_role" "this" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = local.trust_conditions
      }
    ]
  })

  tags = var.tags
}

# Indexed by count rather than for_each. The ARNs are created in the same apply,
# so their values are unknown at plan time and cannot form set keys.
resource "aws_iam_role_policy_attachment" "this" {
  count = length(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.policy_arns[count.index]
}
