# Routes pods in the configured namespaces to Fargate. The cluster has no EC2
# node groups, so a namespace without a profile schedules nothing at all.

# Scoped to this cluster's profiles, so the role cannot run pods for a Fargate
# profile in another account or another cluster.
data "aws_iam_policy_document" "fargate_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${var.cluster_name}/*"]
    }
  }
}

# The name stays at the root path because Fargate profiles cannot change their
# execution role in place: moving it would replace every profile and reschedule
# every pod. The boundary is what caps the role instead, since the api pipeline
# also owns the logging policy attached to it.
resource "aws_iam_role" "fargate" {
  name                 = "${var.cluster_name}-fargate-role"
  assume_role_policy   = data.aws_iam_policy_document.fargate_assume_role.json
  permissions_boundary = var.workload_permissions_boundary
  tags                 = local.common_tags
}

resource "aws_iam_role_policy_attachment" "fargate_execution" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# The OTel Collector namespace is folded in automatically when the Collector is
# installed, so it cannot be left without a profile and fail to schedule.
locals {
  fargate_namespaces = toset(concat(
    var.fargate_namespaces,
    var.install_otel_collector ? [var.otel_collector_namespace] : [],
  ))
}

resource "aws_eks_fargate_profile" "this" {
  for_each = local.fargate_namespaces

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${var.cluster_name}-${each.value}"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = each.value
  }

  tags = local.common_tags
}
