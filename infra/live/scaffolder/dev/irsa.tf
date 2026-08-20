# =============================================================================
# SCAFFOLDER IRSA
# IAM role assumed by the scaffolder worker pod via the cluster OIDC provider,
# plus the annotated ServiceAccount its Deployment binds to (k8s/scaffolder).
# Mirrors provisioner_irsa.tf in the api component; the cluster's OIDC
# coordinates come from SSM rather than a module reference because the cluster
# lives in a different workspace.
# =============================================================================

locals {
  scaffolder_service_account_name      = "internal-developer-platform-scaffolder"
  scaffolder_service_account_namespace = "default"

  eks_oidc_provider_url = data.aws_ssm_parameter.eks_oidc_provider_url.value
}

data "aws_iam_policy_document" "scaffolder_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_ssm_parameter.eks_oidc_provider_arn.value]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.scaffolder_service_account_namespace}:${local.scaffolder_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scaffolder" {
  name               = "${local.name_prefix}-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.scaffolder_assume_role.json
  tags               = local.tags
}

# ONE ROLE, FOR NOW. On Lambda each function had its own, so the handler that
# reserved a name could not read the GitHub App key. A single pod cannot express
# that, and ADR-0004 records the mitigation: split into two Deployments with two
# roles — state operations and GitHub operations — when the GitHub adapter
# lands. Until then this role holds nothing but DynamoDB, the task queue and the
# callback API, so keep it that way and add the second role with the secret.
data "aws_iam_policy_document" "scaffolder" {
  # DynamoDB: the service's own table only. No index ARN — a GSI is queried
  # through the table, and nothing writes to one directly.
  statement {
    sid = "ScaffolderTable"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.scaffolder.arn,
      "${aws_dynamodb_table.scaffolder.arn}/index/*",
    ]
  }

  # SQS: consume side of the task queue. GetQueueUrl is what lets the pod be
  # configured with a queue name instead of an account-qualified URL.
  statement {
    sid = "ScaffolderTaskQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.tasks.arn]
  }

  # Step Functions callbacks. These three take a task token, not a resource
  # ARN, and the API does not support resource-level permissions for them —
  # hence the wildcard. Holding them is meaningless without a valid token.
  statement {
    sid = "ScaffolderTaskCallbacks"
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure",
      "states:SendTaskHeartbeat",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "scaffolder" {
  name        = "${local.name_prefix}-${var.environment}-policy"
  description = "Permissions for the internal-developer-platform scaffolder pod"
  policy      = data.aws_iam_policy_document.scaffolder.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "scaffolder" {
  role       = aws_iam_role.scaffolder.name
  policy_arn = aws_iam_policy.scaffolder.arn
}

resource "kubernetes_service_account" "scaffolder" {
  metadata {
    name      = local.scaffolder_service_account_name
    namespace = local.scaffolder_service_account_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.scaffolder.arn
    }
    labels = {
      "app.kubernetes.io/name"       = local.scaffolder_service_account_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}
