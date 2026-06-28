# =============================================================================
# DATADOG CLUSTER AGENT
# Runs as a single-replica Deployment on Fargate. This is the entity that
# talks to the Kubernetes API to enumerate pods, nodes, and workloads — the
# data Datadog needs to power its K8s inventory pages. Since Fargate clusters
# can't run the upstream Datadog node-agent DaemonSet, the Cluster Agent is
# the only path to cluster-level visibility here. Per-pod metrics/traces/logs
# still come from the datadog-agent sidecar in each application pod.
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

resource "kubernetes_secret" "datadog_api_key" {
  count = var.install_datadog_cluster_agent ? 1 : 0

  metadata {
    name      = "datadog-api-key"
    namespace = kubernetes_namespace.datadog[0].metadata[0].name
  }

  data = {
    api-key = var.datadog_api_key
  }

  type = "Opaque"
}

resource "helm_release" "datadog" {
  count = var.install_datadog_cluster_agent ? 1 : 0

  name       = "datadog"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  namespace  = kubernetes_namespace.datadog[0].metadata[0].name
  version    = var.datadog_chart_version

  # Fargate layout: no DaemonSet (Fargate can't run them), single-replica
  # Cluster Agent, orchestrator explorer on for live pod inventory in Datadog,
  # kube-state-metrics subchart enabled for resource state metrics.
  set = [
    {
      name  = "datadog.apiKeyExistingSecret"
      value = kubernetes_secret.datadog_api_key[0].metadata[0].name
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
    {
      name  = "clusterChecksRunner.enabled"
      value = "false"
    },
  ]

  depends_on = [
    aws_eks_fargate_profile.this,
    kubernetes_secret.datadog_api_key,
  ]
}
