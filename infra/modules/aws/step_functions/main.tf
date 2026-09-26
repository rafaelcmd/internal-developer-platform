# A Step Functions state machine with its execution role, its log group and
# X-Ray tracing. The platform uses it for durable orchestration: a workflow
# whose state survives the death of every process taking part in it, so a
# provisioning request half-finished by a crashed worker is a resumable
# execution rather than a question nobody can answer.

data "aws_caller_identity" "current" {}

# Step Functions writes execution history here when var.log_level is not OFF.
# The log group is created by Terraform rather than left to the service so that
# retention is owned: a vended log group defaults to never expiring.
resource "aws_cloudwatch_log_group" "this" {
  # Step Functions only accepts a destination under /aws/vendedlogs/, and grants
  # itself delivery access to that prefix through a resource policy it manages.
  name              = "/aws/vendedlogs/states/${var.name}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    # Confused-deputy guard. The role cannot be scoped to the state machine ARN
    # it serves, because the machine needs the role to exist before it can be
    # created, so the account is the tightest condition available here.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-execution"
  description        = var.role_description
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# What the machine is allowed to orchestrate: the queues it sends tasks to, the
# tables it writes, anything else the caller passes. Kept as one caller-supplied
# document so the permissions of a workflow read as a single list next to the
# states that use them.
resource "aws_iam_role_policy" "workflow" {
  name   = "${var.name}-workflow"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

# Logging and tracing permissions, which every state machine needs and no caller
# should have to restate.
data "aws_iam_policy_document" "telemetry" {
  # CloudWatch Logs' vended-delivery API takes no resource ARN: the delivery is
  # created against the state machine, which does not exist when this policy is
  # written. AWS documents the wildcard as required.
  dynamic "statement" {
    for_each = var.log_level == "OFF" ? [] : [1]

    content {
      sid = "DeliverExecutionHistory"
      actions = [
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups",
      ]
      resources = ["*"]
    }
  }

  # Sampling decisions and segment uploads are account-level operations with no
  # resource ARN of their own.
  dynamic "statement" {
    for_each = var.tracing_enabled ? [1] : []

    content {
      sid = "PublishTraceSegments"
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "telemetry" {
  count = var.log_level == "OFF" && !var.tracing_enabled ? 0 : 1

  name   = "${var.name}-telemetry"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.telemetry.json
}

resource "aws_sfn_state_machine" "this" {
  name       = var.name
  role_arn   = aws_iam_role.this.arn
  type       = var.type
  definition = var.definition

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this.arn}:*"
    level                  = var.log_level
    include_execution_data = var.log_include_execution_data
  }

  tracing_configuration {
    enabled = var.tracing_enabled
  }

  # The role's policies are attached separately from the role, and a state
  # machine whose first execution starts before they land fails on the first
  # action it takes.
  depends_on = [
    aws_iam_role_policy.workflow,
    aws_iam_role_policy.telemetry,
  ]

  tags = var.tags
}

# A failed execution is a request that stopped halfway. The metric counts whole
# executions rather than states, so one alarm covers every path the definition
# can fail down. Timeouts and aborts are separate metrics and are not covered.
resource "aws_cloudwatch_metric_alarm" "executions_failed" {
  count = var.enable_failure_alarm ? 1 : 0

  alarm_name = "${var.name}-executions-failed"
  alarm_description = join(" ", [
    "Executions of ${var.name} ended in a failed state.",
    "Each one is a provisioning request that did not complete; the execution history holds the state it stopped at.",
  ])

  namespace   = "AWS/States"
  metric_name = "ExecutionsFailed"
  dimensions  = { StateMachineArn = aws_sfn_state_machine.this.arn }

  statistic           = "Sum"
  period              = var.failure_alarm_period
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1

  # Step Functions publishes no datapoint while nothing is running, which is the
  # normal state of a platform this size.
  treat_missing_data = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = var.tags
}
