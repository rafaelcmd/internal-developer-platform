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
  description = "Name of the service being deployed"
  type        = string
  default     = "provisioner"
}

variable "cluster_name" {
  description = "Name of the EKS cluster the pod runs on. Prefixes the IAM role name, matching the api component's convention."
  type        = string
}

# The cross-stack contract. The scaffolder publishes its queue names under
# /idp/<service>/<environment>/, and this stack reads them to target its
# callback tasks.

variable "scaffolder_service_name" {
  description = "Service name the scaffolder stack publishes its SSM parameters under. Changing it here without changing it there breaks the lookup in data.tf."
  type        = string
  default     = "scaffolder"
}

variable "infra_worker_task_queue_name" {
  description = "Queue the ProvisionInfra callback task targets. Null until the infra worker is built, which makes a request naming cloud resources fail rather than report success for resources nothing created."
  type        = string
  default     = null
}

# Request state. The table is the platform's record of what it was asked to
# build and how each request ended.

variable "point_in_time_recovery_enabled" {
  description = "Continuous backups for the request table. Off in dev, on everywhere else."
  type        = bool
  default     = false
}

variable "deletion_protection_enabled" {
  description = "Blocks a destroy from taking the request history with it. Off in dev, on everywhere else."
  type        = bool
  default     = false
}

# Timeouts. Four clocks bound a callback task and they are not interchangeable:
#
#   - the worker's processing time, bounded by nothing but the work itself;
#   - the SQS visibility timeout, which hides a received message from other
#     consumers and on expiry redelivers the task under the same token;
#   - the Step Functions task timeout below, which bounds the whole callback,
#     redeliveries included, and on expiry fails the state;
#   - the execution timeout, which bounds the request end to end.
#
# Each is set above the one before it. The step that matters is the third: a
# task budget must exceed the queue's whole redelivery run, which is its
# visibility timeout multiplied by its redrive limit (300 x 5 = 1500 seconds for
# the scaffolder queues). Below that, a task that can never succeed fails its
# execution while SQS is still retrying, and the dead-letter alarm that would
# have said why arrives after the failure it explains.

variable "reserve_name_timeout_seconds" {
  description = "Callback budget for ReserveName. One conditional write, so the elapsed time is queue wait and redelivery rather than work."
  type        = number
  default     = 1800
}

variable "create_repository_timeout_seconds" {
  description = "Callback budget for CreateRepository, which calls GitHub and can be waiting out a rate limit"
  type        = number
  default     = 1800
}

variable "provision_infra_timeout_seconds" {
  description = "Callback budget for ProvisionInfra. Sized for a Terraform run, which is the longest thing the platform does."
  type        = number
  default     = 3600
}

variable "record_state_timeout_seconds" {
  description = "Budget for one request-state write. A single-item UpdateItem that takes this long has a fault behind it, not load."
  type        = number
  default     = 30
}

variable "execution_timeout_seconds" {
  description = "Ceiling on a whole request. Above the sum of the task budgets, so a slow task is stopped by its own timeout and named in the failure rather than by this one."
  type        = number
  default     = 7200
}

# Execution history and tracing. Both are how a failed provision is read after
# the fact; neither affects what the workflow does.

variable "state_machine_log_level" {
  description = "ALL, ERROR, FATAL or OFF. ALL logs state transitions, which is what makes an execution readable once its history has aged out."
  type        = string
  default     = "ALL"
}

variable "state_machine_log_retention_in_days" {
  description = "Retention on the execution-history log group"
  type        = number
  default     = 30
}

variable "state_machine_tracing_enabled" {
  description = "X-Ray active tracing on the state machine. The execution graph with per-state timings is the fastest way to see which step is slow."
  type        = bool
  default     = true
}
