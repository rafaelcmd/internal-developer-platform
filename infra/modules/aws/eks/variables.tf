# =============================================================================
# INFRASTRUCTURE DEPENDENCIES
# =============================================================================

variable "vpc_id" {
  description = "The ID of the VPC where the EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the EKS control plane ENIs and Fargate pods"
  type        = list(string)
}

# =============================================================================
# GENERAL PROJECT CONFIGURATION
# =============================================================================

variable "aws_region" {
  description = "AWS region where the EKS cluster lives"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

# =============================================================================
# CLUSTER CONFIGURATION
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version of the EKS control plane"
  type        = string
  default     = "1.34"
}

variable "endpoint_private_access" {
  description = "Whether the EKS API server is reachable from inside the VPC"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server is reachable from the public internet — kept open so kubectl works from operator workstations; lock down by CIDR for production"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# =============================================================================
# CLUSTER ACCESS
# IAM principals granted cluster-admin via the Access Entries API. Use this to
# add operator IAM users/roles so `kubectl` works from their workstations — the
# cluster creator (the TFC role) already has admin implicitly.
# =============================================================================

variable "cluster_admin_principal_arns" {
  description = "List of IAM principal ARNs to grant cluster-admin via EKS Access Entries"
  type        = list(string)
  default     = []
}

# =============================================================================
# FARGATE PROFILE CONFIGURATION
# Namespaces routed to Fargate. Anything outside this list won't schedule
# because there are no EC2 nodes attached to this cluster.
# =============================================================================

variable "fargate_namespaces" {
  description = "Kubernetes namespaces whose pods should run on Fargate. kube-system is included so CoreDNS schedules without EC2 nodes."
  type        = list(string)
  default     = ["default", "kube-system"]
}

# =============================================================================
# LOGGING
# =============================================================================

variable "enabled_cluster_log_types" {
  description = "EKS control plane log types to ship to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Retention for the EKS control-plane CloudWatch log group"
  type        = number
  default     = 7
}

variable "fargate_log_retention_days" {
  description = "Retention for the Fargate-pods CloudWatch log group (target of the aws-observability ConfigMap)"
  type        = number
  default     = 7
}

variable "enable_fargate_logging" {
  description = "Configure the aws-observability ConfigMap so Fargate-managed Fluent Bit ships pod stdout/stderr to CloudWatch Logs."
  type        = bool
  default     = false
}

# =============================================================================
# AWS LOAD BALANCER CONTROLLER
# Installed by this module so Service type=LoadBalancer can provision NLBs.
# =============================================================================

variable "install_aws_load_balancer_controller" {
  description = "Install AWS Load Balancer Controller via Helm. Required for Service type=LoadBalancer with NLB target-type=ip on Fargate."
  type        = bool
  default     = true
}

variable "aws_load_balancer_controller_chart_version" {
  description = "Version of the aws-load-balancer-controller Helm chart"
  type        = string
  default     = "1.8.1"
}

variable "aws_load_balancer_controller_namespace" {
  description = "Namespace the AWS Load Balancer Controller runs in"
  type        = string
  default     = "kube-system"
}

# =============================================================================
# DATADOG CLUSTER AGENT
# Cluster-level visibility (pod inventory, orchestrator explorer) on Fargate.
# Fargate can't run a DataDog node-agent DaemonSet, so the Cluster Agent is
# the only path to a populated K8s page in Datadog. Per-pod metrics/traces/
# logs still come from the datadog-agent sidecar inside each app pod.
# =============================================================================

variable "install_datadog_cluster_agent" {
  description = "Install the Datadog Cluster Agent via Helm. Requires datadog_cluster_agent_namespace to be in fargate_namespaces."
  type        = bool
  default     = false
}

variable "datadog_chart_version" {
  description = "Version of the datadog/datadog Helm chart"
  type        = string
  default     = "3.227.1"
}

variable "datadog_cluster_agent_namespace" {
  description = "Namespace the Datadog Cluster Agent runs in. Must be present in fargate_namespaces."
  type        = string
  default     = "datadog"
}

variable "datadog_api_key" {
  description = "Datadog API key consumed by the Cluster Agent (read from SSM upstream). Required when install_datadog_cluster_agent is true."
  type        = string
  default     = null
  sensitive   = true
}

# =============================================================================
# OPENTELEMETRY COLLECTOR
# Cluster-managed prerequisites for the vendor-agnostic telemetry pipeline: the
# observability namespace, an IRSA-annotated ServiceAccount, and a copy of the
# Datadog API key secret. The Collector workload itself is raw manifests under
# /k8s/otel-collector. When enabled, otel_collector_namespace is auto-added to
# the Fargate profile.
# =============================================================================

variable "install_otel_collector" {
  description = "Provision the OTel Collector's cluster prerequisites (namespace, IRSA ServiceAccount, Datadog secret). Reuses datadog_api_key."
  type        = bool
  default     = false
}

variable "otel_collector_namespace" {
  description = "Namespace the OTel Collector runs in. Auto-added to the Fargate profile when install_otel_collector is true."
  type        = string
  default     = "observability"
}

variable "otel_collector_service_account" {
  description = "Name of the OTel Collector ServiceAccount (must match serviceAccountName in k8s/otel-collector/deployment.yaml)"
  type        = string
  default     = "otel-collector"
}

variable "amp_workspace_arn" {
  description = "ARN of an Amazon Managed Prometheus workspace. When set, the Collector's IRSA role is granted aps:RemoteWrite to it. Leave null to use the Datadog exporter only."
  type        = string
  default     = null
}

# =============================================================================
# TAGS
# =============================================================================

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
