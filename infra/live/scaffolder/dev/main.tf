# =============================================================================
# SCAFFOLDER STATE
# One DynamoDB table for the whole service. On-demand billing because scaffold
# traffic is bursty and rare — provisioned capacity would be sized for a peak
# that happens a few times a day.
#
# | Item              | PK                    | SK                |
# |-------------------|-----------------------|-------------------|
# | Template version  | TEMPLATE#<name>       | VERSION#<semver>  |
# | Name reservation  | NAME#<app-name>       | RESERVATION       |
# | Repository record | REPO#<owner>/<name>   | META              |
# =============================================================================

resource "aws_dynamodb_table" "scaffolder" {
  name         = "${local.name_prefix}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  # Abandoned scaffolds release their name automatically. The adapter writes
  # ExpiresAt as epoch seconds, which is the only shape DynamoDB TTL reads.
  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = local.tags
}

# =============================================================================
# TASK QUEUE
# Written as plain resources rather than through modules/aws/sqs: that module is
# shaped for the provisioner's queue and exposes neither a visibility timeout
# nor a redrive policy, both of which this queue needs.
# =============================================================================

resource "aws_sqs_queue" "tasks_dlq" {
  name                      = "${local.name_prefix}-tasks-dlq-${var.environment}"
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = local.tags
}

resource "aws_sqs_queue" "tasks" {
  name = "${local.name_prefix}-tasks-${var.environment}"

  # Long enough for the slowest task to finish before SQS hands the same message
  # to a second consumer. Raise this before adding a task that takes longer than
  # a template render and a push.
  visibility_timeout_seconds = var.task_visibility_timeout_seconds
  message_retention_seconds  = var.task_message_retention_seconds

  # The worker deliberately leaves a message on the queue when it cannot report
  # an outcome to Step Functions, so this redrive is the backstop for a payload
  # no build of the worker can handle.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.tasks_dlq.arn
    maxReceiveCount     = var.task_max_receive_count
  })

  tags = local.tags
}

# Only Step Functions puts messages here. The consume side is the pod's IRSA
# role; nothing else in the account has a reason to send.
data "aws_iam_policy_document" "tasks_queue" {
  statement {
    sid       = "AllowStatesToSendTasks"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.tasks.arn]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "tasks" {
  queue_url = aws_sqs_queue.tasks.id
  policy    = data.aws_iam_policy_document.tasks_queue.json
}

# =============================================================================
# PUBLISHED VALUES
# The pod resolves the table and queue by name from its own environment, so
# these exist for other stacks — the scaffold state machine, when it is built,
# needs the queue ARN to target.
# =============================================================================

resource "aws_ssm_parameter" "table_name" {
  name  = "/idp/${var.service_name}/${var.environment}/table_name"
  type  = "String"
  value = aws_dynamodb_table.scaffolder.name
  tags  = local.tags
}

resource "aws_ssm_parameter" "task_queue_arn" {
  name  = "/idp/${var.service_name}/${var.environment}/task_queue_arn"
  type  = "String"
  value = aws_sqs_queue.tasks.arn
  tags  = local.tags
}

resource "aws_ssm_parameter" "task_queue_name" {
  name  = "/idp/${var.service_name}/${var.environment}/task_queue_name"
  type  = "String"
  value = aws_sqs_queue.tasks.name
  tags  = local.tags
}
