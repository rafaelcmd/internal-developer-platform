
module "tfc_oidc" {
  source         = "../../modules/aws/oidc"
  url            = "https://app.terraform.io"
  client_id_list = ["aws.workload.identity"]
  thumbprint     = var.tfc_thumbprint
  role_name      = var.tfc_role_name
  string_equals  = {
    "app.terraform.io:aud" = "aws.workload.identity"
  }
  string_like    = {
    "app.terraform.io:sub" = var.tfc_allowed_subs
  }
  policy_arns    = var.tfc_policy_arns
  tags           = var.tags
}

