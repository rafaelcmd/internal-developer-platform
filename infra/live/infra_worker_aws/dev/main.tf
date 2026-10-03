# The AWS infra worker's task queue: where the scaffold state machine puts a
# ProvisionInfra callback task for the AWS resources in a request. The worker
# pod consumes it and reports back to Step Functions with the task token. Each
# cloud provider's worker owns a queue of its own; see docs/adr/0008.

module "task_queue" {
  source = "../../../modules/aws/sqs"

  queue_name = "${local.name_prefix}-tasks-${var.environment}"

  # Must exceed the slowest task, or SQS delivers the same message to a second
  # consumer while the first is still working. A Terraform run is far slower
  # than logging a payload, so this has to grow before the worker applies
  # anything.
  visibility_timeout_seconds = var.task_visibility_timeout_seconds
  message_retention_seconds  = var.task_message_retention_seconds

  # The worker leaves a message on the queue when it cannot report an outcome to
  # Step Functions, so redrive is the backstop for a payload no build of the
  # worker can handle.
  max_receive_count             = var.task_max_receive_count
  dlq_message_retention_seconds = var.dlq_message_retention_seconds

  producer_service_principals = ["states.amazonaws.com"]

  # A task in the dead-letter queue is an execution waiting on a token that will
  # never be answered.
  alarm_actions = [data.aws_ssm_parameter.observability_alerts_topic_arn.value]

  tags = local.tags
}

# The state machine targets this queue by name, read from here by the
# provisioner stack, so the two stacks share no state.
resource "aws_ssm_parameter" "task_queue_name" {
  name  = "/idp/${var.service_name}/${var.environment}/task_queue_name"
  type  = "String"
  value = module.task_queue.queue_name
  tags  = local.tags
}

resource "aws_ssm_parameter" "task_queue_arn" {
  name  = "/idp/${var.service_name}/${var.environment}/task_queue_arn"
  type  = "String"
  value = module.task_queue.queue_arn
  tags  = local.tags
}
