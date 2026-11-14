# The AWS side of the Datadog integration: the role Datadog assumes to crawl
# this account, and the policies that bound what it can read. Paired with
# modules/datadog, which registers the integration on the Datadog side and
# supplies the External Id this role's trust policy pins.

resource "aws_iam_role" "datadog_integration_role" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::464622532012:root"
      }
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.external_id
        }
      }
    }]
  })

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# The role's permissions are managed policies owned by the bootstrap stack
# (live/shared/iam-github-oidc), which the datadog pipeline may attach but not
# edit. Owning both the role's trust and its policy text would let that pipeline
# point the role at any account with any permission. See docs/adr/0009.
resource "aws_iam_role_policy_attachment" "integration" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.datadog_integration_role.name
  policy_arn = each.value
}

# Resource collection, which is resources_config.extended_collection on the
# Datadog side, requires AWS's managed SecurityAudit policy in addition to the
# Datadog baseline policy.
resource "aws_iam_role_policy_attachment" "security_audit" {
  role       = aws_iam_role.datadog_integration_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}
