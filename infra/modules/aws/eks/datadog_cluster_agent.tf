# =============================================================================
# DATADOG CLUSTER AGENT + FARGATE SIDECAR INJECTION
# The Cluster Agent (single-replica Deployment) talks to the Kubernetes API to
# enumerate cluster-scoped objects and unscheduled pods. On its own it can NOT
# report the live status of running pods — on Fargate that job belongs to a
# datadog-agent sidecar inside each application pod (a DaemonSet is
# impossible). The Cluster Agent's Admission Controller injects that sidecar
# into any pod labeled `agent.datadoghq.com/sidecar: fargate`; without it the
# Kubernetes Explorer freezes pods at their last reported state (Pending /
# Terminating).
#
# The injected sidecar resolves, by convention, a secret literally named
# `datadog-secret` (keys `api-key` and `token`) in the *application pod's*
# namespace — hence the per-namespace secret copies below. The `token` key is
# the shared Cluster Agent auth token the sidecar uses to forward orchestrator
# data. App telemetry (traces/metrics/logs) is NOT the sidecar's job — that
# still leaves the apps as OTLP to the OTel Collector.
# =============================================================================

resource "kubernetes_namespace" "datadog" {
  count = var.install_datadog_cluster_agent ? 1 : 0

  metadata {
    name = var.datadog_cluster_agent_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_fargate_profile.this]
}

# Shared auth token between the Cluster Agent and injected sidecars. Generated
# here (not by the chart) so it can be replicated into app namespaces.
resource "random_password" "datadog_cluster_agent_token" {
  count = var.install_datadog_cluster_agent ? 1 : 0

  length  = 32
  special = false
}

# Secret consumed by the chart itself (apiKeyExistingSecret +
# clusterAgent.tokenExistingSecret) in the release namespace.
resource "kubernetes_secret" "datadog_secret" {
  count = var.install_datadog_cluster_agent ? 1 : 0

  metadata {
    name      = "datadog-secret"
    namespace = kubernetes_namespace.datadog[0].metadata[0].name
  }

  data = {
    api-key = var.datadog_api_key
    token   = random_password.datadog_cluster_agent_token[0].result
  }

  type = "Opaque"
}

# Copies of the secret in every namespace hosting sidecar-labeled pods — the
# injected container's secretKeyRef only resolves within its own namespace.
resource "kubernetes_secret" "datadog_secret_sidecar" {
  for_each = var.install_datadog_cluster_agent ? toset(var.datadog_sidecar_namespaces) : toset([])

  metadata {
    name      = "datadog-secret"
    namespace = each.value
  }

  data = {
    api-key = var.datadog_api_key
    token   = random_password.datadog_cluster_agent_token[0].result
  }

  type = "Opaque"
}

# The injected sidecar queries the local kubelet with the *application pod's*
# ServiceAccount token, so each SA behind a labeled pod needs kubelet-read
# access (per Datadog's EKS Fargate docs).
resource "kubernetes_cluster_role" "datadog_sidecar" {
  count = var.install_datadog_cluster_agent && length(var.datadog_sidecar_service_accounts) > 0 ? 1 : 0

  metadata {
    name = "datadog-fargate-sidecar"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "namespaces", "endpoints"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes/metrics", "nodes/spec", "nodes/stats", "nodes/proxy", "nodes/pods", "nodes/healthz"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "datadog_sidecar" {
  count = var.install_datadog_cluster_agent && length(var.datadog_sidecar_service_accounts) > 0 ? 1 : 0

  metadata {
    name = "datadog-fargate-sidecar"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.datadog_sidecar[0].metadata[0].name
  }

  dynamic "subject" {
    for_each = var.datadog_sidecar_service_accounts
    content {
      kind      = "ServiceAccount"
      name      = subject.value.name
      namespace = subject.value.namespace
    }
  }
}

resource "helm_release" "datadog" {
  count = var.install_datadog_cluster_agent ? 1 : 0

  name       = "datadog"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  namespace  = kubernetes_namespace.datadog[0].metadata[0].name
  version    = var.datadog_chart_version

  # Every rescheduled pod on Fargate waits on a fresh microVM (1-3 min each);
  # the 5-minute default has proven too tight for multi-deployment rollouts.
  timeout = 600

  # Fargate layout: no DaemonSet (Fargate can't run them), single-replica
  # Cluster Agent, orchestrator explorer on for live pod inventory in Datadog,
  # kube-state-metrics subchart enabled for resource state metrics.
  set = [
    {
      name  = "datadog.apiKeyExistingSecret"
      value = kubernetes_secret.datadog_secret[0].metadata[0].name
    },
    # The bundled datadog-operator subchart does NOT inherit
    # datadog.apiKeyExistingSecret — when its own value is unset it falls back
    # to a secret named `<release>-api-key` (datadog-api-key), which no longer
    # exists. Point it at the same secret explicitly.
    {
      name  = "operator.apiKeyExistingSecret"
      value = kubernetes_secret.datadog_secret[0].metadata[0].name
    },
    {
      name  = "datadog.clusterName"
      value = aws_eks_cluster.this.name
    },
    {
      name  = "datadog.site"
      value = "datadoghq.com"
    },
    {
      name  = "datadog.orchestratorExplorer.enabled"
      value = "true"
    },
    # The legacy bundled kube-state-metrics (v1.9.8) uses 2019-era client-go
    # and floods logs with "Failed to list *v1beta1.X" errors on modern EKS.
    # The Cluster Agent's kubernetes_state_core check (kubeStateMetricsCore,
    # default-enabled in chart 3.x) covers the same metrics with current
    # client-go, in-process, without a separate pod.
    {
      name  = "datadog.kubeStateMetricsEnabled"
      value = "false"
    },
    {
      name  = "agents.enabled"
      value = "false"
    },
    {
      name  = "clusterAgent.enabled"
      value = "true"
    },
    {
      name  = "clusterAgent.replicas"
      value = "1"
    },
    # Fixed token (instead of chart-generated) so sidecars in app namespaces
    # can authenticate to the Cluster Agent with the replicated secret.
    {
      name  = "clusterAgent.tokenExistingSecret"
      value = kubernetes_secret.datadog_secret[0].metadata[0].name
    },
    # Admission Controller webhook injects the datadog-agent sidecar into pods
    # labeled `agent.datadoghq.com/sidecar: fargate` at creation time; the
    # `fargate` provider preset wires DD_EKS_FARGATE and the Cluster Agent
    # connection for orchestrator data.
    {
      name  = "clusterAgent.admissionController.agentSidecarInjection.enabled"
      value = "true"
    },
    {
      name  = "clusterAgent.admissionController.agentSidecarInjection.provider"
      value = "fargate"
    },
    {
      name  = "clusterChecksRunner.enabled"
      value = "false"
    },
  ]

  depends_on = [
    aws_eks_fargate_profile.this,
    kubernetes_secret.datadog_secret,
  ]
}
