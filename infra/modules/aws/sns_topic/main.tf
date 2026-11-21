# A notification topic and its subscriptions. This is the platform's alert
# channel: CloudWatch alarms, such as the dead-letter queue alarms raised by the
# sqs module, publish here.
#
# The topic is a stable address that alarms reference by ARN, while an email
# subscription must be confirmed by a human. Recreating the topic invalidates
# every confirmation, so the topic is kept even with nothing subscribed to it.

resource "aws_sns_topic" "this" {
  name = var.name

  # Alarm payloads are operational metadata rather than secrets. Pass a CMK
  # where the topic will carry anything more sensitive.
  kms_master_key_id = var.kms_master_key_id

  tags = var.tags
}

# Keyed by a caller-chosen label rather than by the endpoint. for_each keys must
# be known at plan time, and an endpoint often is not: a queue or function
# created in the same apply has no ARN until it exists. Deriving the key from
# the endpoint fails with "the for_each value depends on resource attributes
# that cannot be determined until apply". A stable label also keeps unrelated
# subscriptions untouched when one is added or removed.
#
# An email subscription stays "pending confirmation" until the recipient clicks
# the link AWS mails them. A plan does not report that it is still pending, so
# check `aws sns list-subscriptions-by-topic` if alerts are not arriving.
resource "aws_sns_topic_subscription" "this" {
  for_each = var.subscriptions

  topic_arn = aws_sns_topic.this.arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint
}

# Setting a topic policy replaces the one SNS attaches by default, so the first
# statement restates that default: it is what lets this account's CloudWatch
# alarms publish and its operators subscribe. AWS:SourceOwner is the key the
# SNS default uses for that purpose.
#
# The deny refuses any publish made without TLS (aws:SecureTransport). An
# explicit deny on the resource holds whatever the caller's identity policy
# allows.
data "aws_iam_policy_document" "topic" {
  statement {
    sid = "AccountOwnerAccess"
    actions = [
      "SNS:AddPermission",
      "SNS:DeleteTopic",
      "SNS:GetTopicAttributes",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:RemovePermission",
      "SNS:SetTopicAttributes",
      "SNS:Subscribe",
    ]
    resources = [aws_sns_topic.this.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "DenyInsecurePublish"
    effect    = "Deny"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.this.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # For other AWS services, which publish through no permissions of this
  # account's own.
  dynamic "statement" {
    for_each = length(var.publisher_service_principals) > 0 ? [1] : []

    content {
      sid       = "AllowServicesToPublish"
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.this.arn]

      principals {
        type        = "Service"
        identifiers = var.publisher_service_principals
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.topic.json
}

moved {
  from = aws_sns_topic_policy.this[0]
  to   = aws_sns_topic_policy.this
}
