# =============================================================================
# LOG DELIVERY — Fargate-pods log group → Datadog Lambda forwarder
# EKS Fargate's managed Fluent Bit ships pod stdout to the log group created
# by the EKS module; the forwarder Lambda picks it up via this subscription
# and ships it to Datadog. The forwarder already grants logs.amazonaws.com
# Invoke without source_arn (see infra/modules/aws/lambda/main.tf:79-89), so
# no extra aws_lambda_permission is needed.
# =============================================================================

resource "aws_cloudwatch_log_subscription_filter" "fargate_pods_to_datadog" {
  name            = "${var.cluster_name}-fargate-pods-to-datadog"
  log_group_name  = module.eks.fargate_pod_log_group_name
  filter_pattern  = ""
  destination_arn = module.datadog_forwarder.datadog_forwarder_arn
  distribution    = "ByLogStream"
}

# =============================================================================
# ALERTING — out-of-band signal when the log pipeline stalls
# Two CloudWatch alarms on the Datadog forwarder Lambda's own metrics:
#   1) Invocations < 1 over 15 min   → "Fargate logs aren't flowing"
#   2) Errors    > 0 over 5 min      → "forwarder is rejecting messages"
# Both fire to an SNS topic; subscribers (email here) get notified. This is
# the AWS-native equivalent of "tell me when Datadog ingestion is broken"
# without depending on Datadog itself for the alert.
# =============================================================================

resource "aws_sns_topic" "observability_alerts" {
  name = "${var.project}-${var.environment}-observability-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "observability_alerts_email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.observability_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_metric_alarm" "forwarder_no_invocations" {
  alarm_name        = "${var.project}-${var.environment}-datadog-forwarder-no-invocations"
  alarm_description = "Datadog forwarder Lambda hasn't been invoked in the last 15 minutes — Fargate pod logs may not be flowing to Datadog."

  namespace   = "AWS/Lambda"
  metric_name = "Invocations"
  statistic   = "Sum"
  period      = 300
  dimensions = {
    FunctionName = module.datadog_forwarder.function_name
  }

  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 3
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.observability_alerts.arn]
  ok_actions    = [aws_sns_topic.observability_alerts.arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "forwarder_errors" {
  alarm_name        = "${var.project}-${var.environment}-datadog-forwarder-errors"
  alarm_description = "Datadog forwarder Lambda is throwing errors — log delivery to Datadog is degraded."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"
  period      = 300
  dimensions = {
    FunctionName = module.datadog_forwarder.function_name
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.observability_alerts.arn]
  ok_actions    = [aws_sns_topic.observability_alerts.arn]

  tags = local.tags
}
