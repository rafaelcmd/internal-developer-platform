resource "aws_iam_openid_connect_provider" "this" {
  url             = var.url
  client_id_list  = var.client_id_list
  thumbprint_list = [var.thumbprint]
  tags            = var.tags
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
          Federated = aws_iam_openid_connect_provider.this.arn
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

resource "aws_iam_role_policy_attachment" "this" {
  count      = length(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = var.policy_arns[count.index]
}
