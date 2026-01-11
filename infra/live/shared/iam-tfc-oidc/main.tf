data "tls_certificate" "tfc_oidc" {
  url = "https://app.terraform.io"
}

module "tfc_oidc" {
  source         = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/oidc?ref=main"
  url            = "https://app.terraform.io"
  client_id_list = ["aws.workload.identity"]
  thumbprint     = data.tls_certificate.tfc_oidc.certificates[0].sha1_fingerprint
  role_name      = var.tfc_role_name
  string_equals = {
    "app.terraform.io:aud" = "aws.workload.identity"
  }
  string_like = {
    "app.terraform.io:sub" = var.tfc_allowed_subs
  }
  policy_arns = concat(var.tfc_policy_arns, [
    aws_iam_policy.vpc_management.arn,
    aws_iam_policy.iam_management.arn,
    aws_iam_policy.ecr_management.arn,
    aws_iam_policy.cognito_management.arn,
    aws_iam_policy.ecs_management.arn,
    aws_iam_policy.api_gateway_management.arn,
    aws_iam_policy.lambda_management.arn,
    aws_iam_policy.nlb_management.arn,
    aws_iam_policy.sqs_management.arn,
    aws_iam_policy.ssm_management.arn
  ])
  tags        = local.tags
}

