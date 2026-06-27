# =============================================================================
# API IRSA
# IAM role assumed by the API pod via the cluster OIDC provider, plus the
# annotated ServiceAccount the deployment binds to. Mirrors the pattern in
# infra/modules/aws/eks/aws_lb_controller.tf.
# =============================================================================

locals {
  api_service_account_name      = "internal-developer-platform-api"
  api_service_account_namespace = "default"
}

data "aws_iam_policy_document" "api_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.api_service_account_namespace}:${local.api_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "${var.cluster_name}-api"
  assume_role_policy = data.aws_iam_policy_document.api_assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "api" {
  # SSM: the API reads its runtime config from two prefixes —
  #   /INTERNAL_DEVELOPER_PLATFORM/*   (queue URL, Redis addr)
  #   /idp/shared/identity/*           (Cognito user-pool / client IDs)
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/INTERNAL_DEVELOPER_PLATFORM/*",
      "arn:aws:ssm:${var.aws_region}:*:parameter/idp/shared/identity/*",
    ]
  }

  # SQS: the API publishes provisioning requests to the provisioner queue.
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [module.sqs.queue_arn]
  }

  # Cognito: signup/login flow. User pool ARN is read from SSM (published by
  # shared/identity) instead of terraform_remote_state, matching the rest of
  # the SSM-decoupled graph.
  statement {
    actions = [
      "cognito-idp:SignUp",
      "cognito-idp:ConfirmSignUp",
      "cognito-idp:InitiateAuth",
    ]
    resources = [data.aws_ssm_parameter.cognito_user_pool_arn.value]
  }
}

resource "aws_iam_policy" "api" {
  name        = "${var.cluster_name}-api-policy"
  description = "Permissions for the internal-developer-platform API pod"
  policy      = data.aws_iam_policy_document.api.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "api" {
  role       = aws_iam_role.api.name
  policy_arn = aws_iam_policy.api.arn
}

resource "kubernetes_service_account" "api" {
  metadata {
    name      = local.api_service_account_name
    namespace = local.api_service_account_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.api.arn
    }
    labels = {
      "app.kubernetes.io/name"       = local.api_service_account_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}
