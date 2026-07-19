# =============================================================================
# OPENTELEMETRY COLLECTOR — cluster-managed prerequisites
#
# The Collector workload itself (Deployment/Service/ConfigMap/RBAC) lives as raw
# manifests in /k8s/otel-collector. This file provisions the pieces that must be
# Terraform-owned because they depend on cluster identity:
#
#   1. The `observability` namespace (also auto-added to the Fargate profile in
#      fargate.tf, so the pod can schedule — Fargate has no default nodes).
#   2. An IRSA-annotated ServiceAccount. IRSA is only strictly needed once an
#      AWS-authenticated exporter is added (Amazon Managed Prometheus remote
#      write signs with SigV4); the datadog exporter needs no AWS auth. Wiring
#      the role now makes adding AMP a config-only change.
#   3. A copy of the Datadog API key secret in the observability namespace,
#      consumed by the Collector's datadog exporter.
#
# Mirrors the IRSA + ServiceAccount pattern used for the AWS Load Balancer
# Controller (aws_lb_controller.tf).
# =============================================================================

resource "kubernetes_namespace" "observability" {
  count = var.install_otel_collector ? 1 : 0

  metadata {
    name = var.otel_collector_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_fargate_profile.this]
}

# -----------------------------------------------------------------------------
# IRSA ROLE
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "otel_collector_assume_role" {
  count = var.install_otel_collector ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.otel_collector_namespace}:${var.otel_collector_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "otel_collector" {
  count = var.install_otel_collector ? 1 : 0

  name               = "${var.cluster_name}-otel-collector"
  assume_role_policy = data.aws_iam_policy_document.otel_collector_assume_role[0].json
  tags               = local.common_tags
}

# Amazon Managed Prometheus remote-write permission — attached only when an AMP
# workspace ARN is supplied. Until then the Collector role has no policies and
# the datadog exporter path works without any AWS permissions.
data "aws_iam_policy_document" "otel_collector_amp" {
  count = var.install_otel_collector && var.amp_workspace_arn != null ? 1 : 0

  statement {
    actions   = ["aps:RemoteWrite"]
    resources = [var.amp_workspace_arn]
  }
}

resource "aws_iam_policy" "otel_collector_amp" {
  count = var.install_otel_collector && var.amp_workspace_arn != null ? 1 : 0

  name        = "${var.cluster_name}-otel-collector-amp"
  description = "Allow the OTel Collector to remote-write to Amazon Managed Prometheus"
  policy      = data.aws_iam_policy_document.otel_collector_amp[0].json
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "otel_collector_amp" {
  count = var.install_otel_collector && var.amp_workspace_arn != null ? 1 : 0

  role       = aws_iam_role.otel_collector[0].name
  policy_arn = aws_iam_policy.otel_collector_amp[0].arn
}

# -----------------------------------------------------------------------------
# SERVICE ACCOUNT (IRSA-annotated) — referenced by the Collector Deployment
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "otel_collector" {
  count = var.install_otel_collector ? 1 : 0

  metadata {
    name      = var.otel_collector_service_account
    namespace = kubernetes_namespace.observability[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.otel_collector[0].arn
    }
    labels = {
      "app.kubernetes.io/name"       = "otel-collector"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# DATADOG API KEY SECRET — consumed by the Collector's datadog exporter
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "otel_datadog_api_key" {
  count = var.install_otel_collector ? 1 : 0

  metadata {
    name      = "datadog-api-key"
    namespace = kubernetes_namespace.observability[0].metadata[0].name
  }

  data = {
    api-key = var.datadog_api_key
  }

  type = "Opaque"
}
