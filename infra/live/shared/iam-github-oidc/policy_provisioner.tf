# CI role for the provisioner component (live/provisioner/dev).
# The scaffold state machine and its execution role, the request-state table,
# and the consumer's own IRSA role plus the ServiceAccount it annotates.
#
# The queue, the cluster and the scaffolder's task queues belong to other
# components; this pipeline reads them (eks:DescribeCluster for the kubernetes
# provider's exec auth, sqs:Get* to resolve the queues the state machine targets
# and the queue the consumer reads) and modifies none of them. The SSM
# parameters it reads and writes are covered by the common policy.
#
# iam:PassRole is the one grant here that is not a create: a state machine names
# the role it assumes, and IAM treats handing a role to a service as its own
# privilege. It is restricted to roles this project tagged and to Step Functions
# as the consuming service, so the pipeline cannot pass an unrelated role.

resource "aws_iam_policy" "pipeline_provisioner" {
  name        = "${var.project}-${var.environment}-pipeline-provisioner-policy"
  description = "Pipeline policy for the provisioner stack (Step Functions, DynamoDB, IRSA)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadServicesInStack"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "sqs:List*",
          "sqs:Get*",
          "dynamodb:List*",
          "dynamodb:Describe*",
          "states:List*",
          "states:Describe*",
          "logs:Describe*",
          "logs:ListTagsForResource",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListTagsForResource"
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
        Sid    = "StepFunctionsCreateTagged"
        Effect = "Allow"
        Action = [
          "states:CreateStateMachine",
          "states:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        # State machines carry no resource-tag condition key for these actions,
        # so they are scoped by name, using the prefix every state machine in
        # this project shares.
        Sid    = "StepFunctionsManageProjectStateMachines"
        Effect = "Allow"
        Action = [
          "states:UpdateStateMachine",
          "states:DeleteStateMachine",
          "states:UntagResource"
        ]
        Resource = "arn:aws:states:*:*:stateMachine:${var.project}-*"
      },
      {
        # Creating a state machine means naming the role it assumes, which IAM
        # authorizes separately from creating either one.
        Sid      = "PassStateMachineExecutionRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
            "iam:PassedToService"     = "states.amazonaws.com"
          }
        }
      },
      {
        # The execution-history log group. Step Functions only delivers into the
        # /aws/vendedlogs/states/ prefix, so the grant needs to reach no further.
        Sid    = "CloudWatchLogsManageStateMachineLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/vendedlogs/states/${var.project}-*"
      },
      {
        # Setting up the delivery itself, and the log-group resource policy that
        # authorizes it. Both are account-level calls that take no resource ARN.
        Sid    = "CloudWatchLogsManageStateMachineDelivery"
        Effect = "Allow"
        Action = [
          "logs:PutResourcePolicy",
          "logs:DeleteResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries"
        ]
        Resource = "*"
      },
      {
        # The failed-execution alarm the step_functions module creates. Without
        # it a provisioning request that dies halfway is only visible to someone
        # already reading the console.
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
        # PutMetricAlarm appears here as well as above: updating an existing
        # alarm is the same call, and a request that does not resend the tags is
        # authorized against the alarm's tags rather than the request's.
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
