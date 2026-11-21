# A Secrets Manager secret, the customer-managed KMS key that encrypts it, and
# an alias for that key. Holds credentials the platform must not keep in
# Terraform, such as the scaffolder's GitHub App private key.
#
# The module creates the secret but no secret version, and takes no input for
# the value. The material is written out of band with
# `aws secretsmanager put-secret-value`, so it never passes through a plan, a
# state file or a CI log. Omitting the input makes that structural rather than a
# convention.
#
# Reading the value is gated twice, on the resources themselves: the secret's
# resource policy denies GetSecretValue to every principal outside
# var.reader_role_arns, and the key policy grants kms:Decrypt of real secret
# versions to those roles only. Both hold even when an identity policy elsewhere
# in the account is broader than intended. The key costs roughly $1/month and
# keeps billing through its deletion window after a destroy.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_root            = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  secrets_manager_service = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
}

# Every statement names the account root as principal, which hands the decision
# to IAM policies in this account and keeps the key manageable if a role is
# replaced. KMS also validates named role principals when the policy is set, so
# naming a role created later in the same apply would fail; the readers are
# matched on aws:PrincipalArn instead.
data "aws_iam_policy_document" "key" {
  # Administration only. Every cryptographic action is left out, and so is
  # kms:CreateGrant, since a grant can hand decryption to any principal.
  statement {
    sid = "KeyAdministration"
    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListGrants",
      "kms:ListKeyPolicies",
      "kms:ListKeyRotations",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:RetireGrant",
      "kms:RevokeGrant",
      "kms:RotateKeyOnDemand",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  # Writing a secret version encrypts but never decrypts, so whoever puts the
  # value needs only these. They work only when Secrets Manager is the caller.
  statement {
    sid       = "EncryptThroughSecretsManager"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.secrets_manager_service]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Secrets Manager checks that the caller can use the key when a secret is
  # created against it, with a Decrypt call carrying this fixed version ID. The
  # condition confines the grant to that check, which decrypts no secret
  # material.
  statement {
    sid       = "ValidateKeyAccessThroughSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.secrets_manager_service]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:SecretVersionId"
      values   = ["RequestToValidateKeyAccess"]
    }
  }

  # The pipeline that creates the secret needs grants made on behalf of Secrets
  # Manager. kms:GrantIsForAWSResource keeps a caller from issuing a grant
  # directly to a principal of its choosing.
  statement {
    sid       = "GrantsForSecretsManager"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.secrets_manager_service]
    }
  }

  statement {
    sid       = "ReadersDecryptThroughSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.secrets_manager_service]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = var.reader_role_arns
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.kms_key_description != null ? var.kms_key_description : "Encrypts ${var.name}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  policy                  = data.aws_iam_policy_document.key.json

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = var.alias_name
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = var.description
  kms_key_id  = aws_kms_key.this.arn

  # Zero lets a destroy/apply cycle reuse the name immediately. Anything higher
  # keeps the name reserved and fails the next apply with "already scheduled for
  # deletion". Use zero only in environments rebuilt from scratch.
  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

# An explicit deny on the resource overrides any Allow in an identity policy,
# including a broad one such as an administrator's. aws:PrincipalArn of an
# assumed-role session is the role's ARN, path included, so the role need not
# exist when this policy is set.
data "aws_iam_policy_document" "secret" {
  statement {
    sid       = "DenyReadingOutsideNamedReaders"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = var.reader_role_arns
    }
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  secret_arn          = aws_secretsmanager_secret.this.arn
  policy              = data.aws_iam_policy_document.secret.json
  block_public_policy = true
}
