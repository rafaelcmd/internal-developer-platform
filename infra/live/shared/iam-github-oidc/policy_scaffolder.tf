# scaffolder component — infra/live/scaffolder/dev.
# The scaffolder's own state (one DynamoDB table), its Step Functions task queue
# and DLQ, and the IRSA role + policy its pod assumes. The kubernetes provider in
# that stack authenticates through eks:DescribeCluster, which is why the read
# statement includes it — the stack reads the cluster but never modifies it.
# The SSM parameters it publishes are covered by the common policy.

resource "aws_iam_policy" "pipeline_scaffolder" {
  name        = "${var.project}-${var.environment}-pipeline-scaffolder-policy"
  description = "Pipeline policy for the scaffolder stack (DynamoDB, SQS, IRSA)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadServicesInStack"
        Effect = "Allow"
        Action = [
          "dynamodb:List*",
          "dynamodb:Describe*",
          "sqs:List*",
          "sqs:Get*",
          "eks:DescribeCluster",
          "states:List*",
          "states:Describe*"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBCreateTagged"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "DynamoDBManageProjectTables"
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteTable",
          "dynamodb:UpdateTable",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:CreateTableReplica",
          "dynamodb:DeleteTableReplica",
          "dynamodb:UntagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
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
        # scoped by queue name instead — the same prefix every resource in this
        # stack is named with.
        Sid    = "SQSManageScaffolderQueues"
        Effect = "Allow"
        Action = [
          "sqs:DeleteQueue",
          "sqs:SetQueueAttributes",
          "sqs:UntagQueue",
          "sqs:AddPermission",
          "sqs:RemovePermission"
        ]
        Resource = "arn:aws:sqs:*:*:${var.project}-scaffolder-*"
      },
      {
        Sid    = "IAMCreateTaggedRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:CreatePolicy",
          "iam:TagRole",
          "iam:TagPolicy"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "IAMManageProjectRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:TagPolicy",
          "iam:UntagPolicy"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      }
    ]
  })

  tags = local.tags
}
