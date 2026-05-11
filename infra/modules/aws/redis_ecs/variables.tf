# =============================================================================
# REDIS-ON-ECS MODULE
# Runs a single Fargate Redis container behind Cloud Map private DNS so all
# API replicas share one centralized cache. No persistence — keys live in memory
# and disappear if the task is replaced. Acceptable for a 24h idempotency cache;
# revisit with EFS or ElastiCache if you need durability.
# =============================================================================

variable "service_name" {
  description = "Logical name of the Redis service (used for ECS service, task family, log group)"
  type        = string
  default     = "redis"
}

variable "container_image" {
  description = "Container image for Redis"
  type        = string
  default     = "public.ecr.aws/docker/library/redis:7.4-alpine"
}

variable "container_port" {
  description = "Port Redis listens on inside the container"
  type        = number
  default     = 6379
}

variable "cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory (MiB)"
  type        = number
  default     = 512
}

variable "max_memory_mb" {
  description = "Redis maxmemory setting in MiB (kept below task memory to leave headroom for the kernel)"
  type        = number
  default     = 384
}

variable "maxmemory_policy" {
  description = "Eviction policy when maxmemory is reached"
  type        = string
  default     = "allkeys-lru"
}

# =============================================================================
# CLUSTER + NETWORK
# =============================================================================

variable "cluster_id" {
  description = "ID of the existing ECS cluster to attach to"
  type        = string
}

variable "vpc_id" {
  description = "VPC where the service runs"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate task"
  type        = list(string)
}

variable "ingress_security_group_ids" {
  description = "Security groups allowed to reach Redis on container_port (e.g. the API task SG)"
  type        = list(string)
}

# =============================================================================
# SERVICE DISCOVERY
# =============================================================================

variable "service_discovery_namespace_name" {
  description = "Cloud Map private DNS namespace name (e.g. internal.idp.local). Created by this module."
  type        = string
}

variable "service_discovery_dns_ttl" {
  description = "DNS record TTL in seconds — kept short so failover propagates quickly when the task is replaced"
  type        = number
  default     = 10
}

# =============================================================================
# IAM
# =============================================================================

variable "task_execution_role_name" {
  description = "Name of the IAM role ECS uses to pull the image and write logs"
  type        = string
}

variable "task_role_name" {
  description = "Name of the IAM role assumed by the running task (Redis itself doesn't need AWS permissions)"
  type        = string
}

# =============================================================================
# OBSERVABILITY
# =============================================================================

variable "log_group_name" {
  description = "CloudWatch log group for Redis container logs"
  type        = string
}

variable "log_retention_days" {
  description = "Days of CloudWatch log retention"
  type        = number
  default     = 7
}

# =============================================================================
# SSM PARAMETER (so the API can resolve the endpoint)
# =============================================================================

variable "ssm_parameter_name" {
  description = "SSM parameter name storing host:port of the Redis endpoint"
  type        = string
}

variable "ssm_parameter_type" {
  description = "Type of the SSM parameter"
  type        = string
  default     = "String"
}

# =============================================================================
# COMMON
# =============================================================================

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
