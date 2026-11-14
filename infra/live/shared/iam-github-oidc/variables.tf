variable "environment" {
  description = "Environment name (e.g., prod, staging, dev) used for resource naming and tagging"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used for tagging"
  type        = string
  default     = "internal-developer-platform"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "owner/name of the repository whose workflows may assume the pipeline roles. Used in sub and job_workflow_ref trust conditions."
  type        = string
  default     = "rafaelcmd/internal-developer-platform"
}

# Names can be renamed or reclaimed by another account; these numeric IDs
# cannot, so a repository re-created under the same name does not inherit trust.
# Read them with: gh api repos/<owner>/<name> --jq '.id, .owner.id'
variable "github_repository_id" {
  description = "Immutable numeric ID of the GitHub repository, pinned in every pipeline role's trust policy"
  type        = string
  default     = "863077094"
}

variable "github_repository_owner_id" {
  description = "Immutable numeric ID of the repository's owner account, pinned in every pipeline role's trust policy"
  type        = string
  default     = "10072172"
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster the api component creates. The api pipeline may manage only the cluster and Fargate roles derived from it."
  type        = string
  default     = "internal-developer-platform-cluster"
}

variable "api_gateway_name" {
  description = "Name of the REST API the api-gateway component creates. The api-gateway pipeline may manage only the CloudWatch role derived from it."
  type        = string
  default     = "internal-developer-platform-api"
}

variable "datadog_role_name" {
  description = "Name of the IAM role Datadog assumes, as set in live/shared/datadog. The datadog pipeline may manage only this role."
  type        = string
  default     = "DatadogIntegrationRole"
}
