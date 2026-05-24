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
  default     = "1.33"
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
# TAGS
# =============================================================================

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
