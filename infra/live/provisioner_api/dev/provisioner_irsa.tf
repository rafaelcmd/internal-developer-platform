# =============================================================================
# PROVISIONER IRSA
# IAM role assumed by the provisioner consumer pod via the cluster OIDC
# provider, plus the annotated ServiceAccount its Deployment binds to
# (k8s/provisioner). Mirrors api_irsa.tf.
# =============================================================================

locals {
  provisioner_service_account_name      = "internal-developer-platform-provisioner"
  provisioner_service_account_namespace = "default"
}

data "aws_iam_policy_document" "provisioner_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.provisioner_service_account_namespace}:${local.provisioner_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "provisioner" {
  name               = "${var.cluster_name}-provisioner"
  assume_role_policy = data.aws_iam_policy_document.provisioner_assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "provisioner" {
  # SSM: the consumer resolves the queue URL from
  # /INTERNAL_DEVELOPER_PLATFORM/SQS_QUEUE_URL at startup.
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/INTERNAL_DEVELOPER_PLATFORM/*",
    ]
  }

  # SQS: consume side of the provisioning queue (the API holds the send side).
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [module.sqs.queue_arn]
  }
}

resource "aws_iam_policy" "provisioner" {
  name        = "${var.cluster_name}-provisioner-policy"
  description = "Permissions for the internal-developer-platform provisioner pod"
  policy      = data.aws_iam_policy_document.provisioner.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "provisioner" {
  role       = aws_iam_role.provisioner.name
  policy_arn = aws_iam_policy.provisioner.arn
}

resource "kubernetes_service_account" "provisioner" {
  metadata {
    name      = local.provisioner_service_account_name
    namespace = local.provisioner_service_account_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.provisioner.arn
    }
    labels = {
      "app.kubernetes.io/name"       = local.provisioner_service_account_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}
