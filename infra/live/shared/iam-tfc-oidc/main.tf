# The Terraform Cloud OIDC provider, the counterpart to iam-github-oidc.
#
# No role trusts it. Terraform Cloud holds state only; runs execute on the
# GitHub runner in Local execution mode, so a stack is always applied by its
# own github-actions-tf-<component> role. A remote-execution path would add a
# role here with modules/aws/oidc_role, scoped and bounded like the pipeline
# roles in iam-github-oidc. See docs/adr/0009.

data "tls_certificate" "tfc_oidc" {
  url = "https://app.terraform.io"
}

module "tfc_oidc" {
  source         = "../../../modules/aws/oidc"
  url            = "https://app.terraform.io"
  client_id_list = ["aws.workload.identity"]
  thumbprint     = data.tls_certificate.tfc_oidc.certificates[0].sha1_fingerprint
  tags           = local.tags
}
