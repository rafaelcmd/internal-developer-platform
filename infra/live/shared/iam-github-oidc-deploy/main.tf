data "tls_certificate" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"
}

module "github_actions_oidc" {
  source         = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/oidc?ref=main"
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint     = data.tls_certificate.github_oidc.certificates[0].sha1_fingerprint
  role_name      = var.github_role_name
  string_equals  = {
    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
  }
  string_like    = {
    "token.actions.githubusercontent.com:sub" = var.github_allowed_subs
  }
  policy_arns    = var.github_policy_arns
  tags           = local.tags
}
