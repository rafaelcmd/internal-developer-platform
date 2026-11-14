# CI role for the AWS infra worker component (live/infra_worker_aws/dev).
# The worker's task queue and DLQ, the dead-letter alarm, and the IRSA role +
# policy its pod assumes, under /idp/workload/infra-worker-aws/ with the
# workload boundary (local.workload_iam_statements). The kubernetes provider in that stack authenticates
# through eks:DescribeCluster to create the ServiceAccount; the stack reads the
# cluster but never modifies it. The SSM parameters it reads and publishes are
# covered by the common policy.

resource "aws_iam_policy" "pipeline_infra_worker_aws" {
  name        = "${var.project}-${var.environment}-pipeline-infra-worker-aws-policy"
  description = "Pipeline policy for the AWS infra worker stack (SQS, IRSA)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "ReadServicesInStack"
        Effect = "Allow"
        Action = [
          "sqs:List*",
          "sqs:Get*",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListTagsForResource",
          "eks:DescribeCluster"
        ]
        Resource = "*"
      },
      {
        Sid    = "SQSCreateTagged"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:TagQueue"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        # SQS has no resource-tag condition key for these actions, so they are
        # scoped by queue name, using the prefix every queue in this stack
        # shares.
        Sid    = "SQSManageInfraWorkerQueues"
        Effect = "Allow"
        Action = [
          "sqs:DeleteQueue",
          "sqs:SetQueueAttributes",
          "sqs:UntagQueue",
          "sqs:AddPermission",
          "sqs:RemovePermission"
        ]
        Resource = "arn:aws:sqs:*:*:${var.project}-infra-worker-aws-*"
      },
      {
        Sid    = "CloudWatchCreateTaggedAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        # PutMetricAlarm appears here as well as above: an update that does not
        # resend the tags is authorized against the alarm's tags rather than
        # the request's.
        Sid    = "CloudWatchManageProjectAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:UntagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      }
    ], local.workload_iam_statements["infra-worker-aws"])
  })

  tags = local.tags
}
