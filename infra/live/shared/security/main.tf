# Account-level visibility into how IAM is used. Nothing in the platform reads
# these resources at runtime; they exist so a person can see what the identity
# policies allow in practice and who used them.
#
# The external-access analyzer reports every resource policy or trust that
# admits a principal outside this account; the Datadog integration role is the
# one expected finding. The unused-access analyzer reports roles, keys and
# permissions nobody has exercised, which is how least privilege is measured
# rather than assumed. It is billed per role and user analyzed each month.

data "aws_caller_identity" "current" {}

resource "aws_accessanalyzer_analyzer" "external_access" {
  analyzer_name = "${var.project}-external-access"
  type          = "ACCOUNT"

  tags = local.tags
}

resource "aws_accessanalyzer_analyzer" "unused_access" {
  analyzer_name = "${var.project}-unused-access"
  type          = "ACCOUNT_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access_age_days
    }
  }

  tags = local.tags
}

# The trail is optional because an account may already record management
# events through a trail created elsewhere. Check with
# `aws cloudtrail describe-trails` before the first apply.
module "cloudtrail" {
  source = "../../../modules/aws/cloudtrail"
  count  = var.enable_cloudtrail ? 1 : 0

  name               = "${var.project}-account-trail"
  bucket_name        = "${var.project}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  log_retention_days = var.cloudtrail_log_retention_days

  tags = local.tags
}

# Applies only to IAM users with a console password. Human access belongs in
# IAM Identity Center, whose sessions are short-lived and MFA-backed; this
# policy sets the floor for any IAM user that still signs in with a password.
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}
