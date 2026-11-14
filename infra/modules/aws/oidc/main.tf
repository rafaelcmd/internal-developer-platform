# An IAM OIDC provider: the trust anchor that lets an external issuer exchange
# its tokens for temporary AWS credentials, so no long-lived access key exists
# in any secret store.
#
# An account holds only one provider per issuer URL, so this module runs once
# per issuer. Roles that trust the provider are built with modules/aws/oidc_role,
# each with its own trust conditions and permissions.

resource "aws_iam_openid_connect_provider" "this" {
  url             = var.url
  client_id_list  = var.client_id_list
  thumbprint_list = [var.thumbprint]
  tags            = var.tags
}
