module "github_actions_oidc" {
  source         = "../../../modules/aws/oidc"
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint     = var.github_thumbprint
  role_name      = var.github_role_name
  string_equals  = {
    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
  }
  string_like    = {
    "token.actions.githubusercontent.com:sub" = var.github_allowed_subs
  }
  policy_arns    = var.github_policy_arns
  tags           = var.tags
}
