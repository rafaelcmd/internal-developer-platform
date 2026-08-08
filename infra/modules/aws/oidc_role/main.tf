# Creates an IAM role assumable through an existing OIDC provider.
#
# Distinct from modules/aws/oidc, which creates the provider *and* one role:
# an account may only hold one provider per issuer URL, so every role beyond
# the first must attach to the provider that module already created.

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
        Condition = {
          StringEquals = var.string_equals
          StringLike   = var.string_like
        }
      }
    ]
  })

  tags = var.tags
}

# Indexed by count rather than for_each: the ARNs are created in the same
# apply, so their values are unknown at plan time and cannot form set keys.
resource "aws_iam_role_policy_attachment" "this" {
  count = length(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.policy_arns[count.index]
}
