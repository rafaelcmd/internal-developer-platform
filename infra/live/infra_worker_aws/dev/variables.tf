variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev) used for resource naming and tagging"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
}

variable "service_name" {
  description = "Name of the service being deployed. Prefixes the queue and role names and the SSM path the provisioner stack reads the queue name from."
  type        = string
  default     = "infra-worker-aws"
}

variable "task_visibility_timeout_seconds" {
  description = "How long a received task is hidden from other consumers. Must exceed the slowest task the worker runs."
  type        = number
  default     = 300
}

variable "task_message_retention_seconds" {
  description = "How long an unconsumed task survives. A task older than this has already lost its execution."
  type        = number
  default     = 86400
}

variable "task_max_receive_count" {
  description = "Deliveries before a task is moved to the DLQ. Visibility timeout times this must stay below the state machine's provision_infra_timeout_seconds."
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "How long a dead-lettered task is kept for inspection"
  type        = number
  default     = 1209600
}
