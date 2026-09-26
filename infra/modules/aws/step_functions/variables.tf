variable "name" {
  description = "Name of the state machine. Producers resolve it by name or by the ARN published alongside it, so this is a contract with them."
  type        = string
}

variable "definition" {
  description = "The Amazon States Language definition, as JSON"
  type        = string
}

variable "type" {
  description = "STANDARD or EXPRESS. Only STANDARD supports .waitForTaskToken and executions longer than five minutes."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.type)
    error_message = "type must be STANDARD or EXPRESS."
  }
}

variable "policy_json" {
  description = "IAM policy document granting the machine what its states call: queues it sends to, tables it writes, functions it invokes"
  type        = string
}

variable "role_description" {
  description = "Description of the execution role, shown in the IAM console next to a name that is otherwise just the machine's"
  type        = string
  default     = null
}

# Execution history is the record of what a workflow did and where it stopped.
# Without it, a failed execution can only be read for as long as Step Functions
# keeps its history, and never queried.

variable "log_level" {
  description = "ALL, ERROR, FATAL or OFF. ALL includes the state transitions, which is what makes an execution readable after the fact."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.log_level)
    error_message = "log_level must be ALL, ERROR, FATAL or OFF."
  }
}

variable "log_include_execution_data" {
  description = "Log each state's input and output. Turn off where a payload carries data that should not reach CloudWatch Logs."
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "Retention on the execution-history log group. A vended log group defaults to never expiring, so this is always set."
  type        = number
  default     = 30
}

variable "log_kms_key_arn" {
  description = "Customer-managed key encrypting the log group. Null uses the CloudWatch Logs service key."
  type        = string
  default     = null
}

variable "tracing_enabled" {
  description = "X-Ray active tracing. The execution graph with per-state timings is the fastest way to see which step is slow."
  type        = bool
  default     = true
}

variable "enable_failure_alarm" {
  description = "Alarm on failed executions"
  type        = bool
  default     = true
}

variable "failure_alarm_period" {
  description = "Seconds between evaluations of the failed-execution alarm"
  type        = number
  default     = 300
}

variable "alarm_actions" {
  description = "ARNs notified when the alarm changes state, typically an SNS topic. An alarm with no actions is visible in CloudWatch but notifies nobody."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the state machine, its role, its log group and the alarm"
  type        = map(string)
  default     = {}
}
