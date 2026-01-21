resource "aws_iam_policy" "provisioner_api_app_policy" {
  name        = "${var.project}-${var.environment}-provisioner-api-app-policy"
  description = "Least privilege policy for managing Application resources (ECS, Lambda, API Gateway, SQS)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECS Statements
      {
        Sid    = "ECSRead"
        Effect = "Allow"
        Action = [
          "ecs:List*",
          "ecs:Describe*",
          "ecs:Get*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSCreateTagged"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:CreateService",
          "ecs:RunTask",
          "ecs:StartTask",
          "ecs:RegisterTaskDefinition",
          "ecs:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "ECSManageProjectResources"
        Effect = "Allow"
        Action = [
          "ecs:DeleteCluster",
          "ecs:UpdateCluster",
          "ecs:DeleteService",
          "ecs:UpdateService",
          "ecs:StopTask",
          "ecs:UntagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "ECSManageTaskDefinitions"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Sid      = "IAMPassRoleECS"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:AssociatedResourceARN" = [
              "arn:aws:ecs:*:*:task-definition/*",
              "arn:aws:lambda:*:*:function:*"
            ]
          }
        }
      },
      # Lambda Statements
      {
        Sid    = "LambdaRead"
        Effect = "Allow"
        Action = [
          "lambda:List*",
          "lambda:Get*"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaCreateTagged"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:TagResource",
          "lambda:PublishLayerVersion",
          "lambda:CreateEventSourceMapping"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "LambdaManageProjectResources"
        Effect = "Allow"
        Action = [
          "lambda:DeleteFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:InvokeFunction",
          "lambda:UntagResource",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:PutFunctionConcurrency",
          "lambda:DeleteFunctionConcurrency",
          "lambda:PublishVersion",
          "lambda:DeleteLayerVersion",
          "lambda:DeleteEventSourceMapping",
          "lambda:UpdateEventSourceMapping"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      # API Gateway Statements
      {
        Sid    = "APIGatewayRead"
        Effect = "Allow"
        Action = [
          "apigateway:GET"
        ]
        Resource = "*"
      },
      {
        Sid    = "APIGatewayManageUntagged"
        Effect = "Allow"
        Action = [
          "apigateway:PATCH",
          "apigateway:PUT",
          "apigateway:DELETE"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/Project" = "true"
          }
        }
      },
      {
        Sid    = "APIGatewayCreateTagged"
        Effect = "Allow"
        Action = [
          "apigateway:POST",
          "apigateway:TagResource",
          "apigateway:PATCH"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "APIGatewayManageProjectResources"
        Effect = "Allow"
        Action = [
          "apigateway:DELETE",
          "apigateway:PUT",
          "apigateway:PATCH",
          "apigateway:UntagResource",
          "apigateway:TagResource",
          "apigateway:POST"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:ResourceTag/Project" = [
               var.project,
               "*" 
            ]
          }
        }
      },
      {
        Sid    = "APIGatewayManageTags"
        Effect = "Allow"
        Action = [
          "apigateway:POST",
          "apigateway:DELETE"
        ]
        Resource = [
          "arn:aws:apigateway:*::/tags/*"
        ]
      },
      {
        Sid    = "APIGatewayManageDeployments"
        Effect = "Allow"
        Action = [
          "apigateway:POST"
        ]
        Resource = [
          "arn:aws:apigateway:*::/apis/*/deployments"
        ]
      },
      # CloudWatch Logs Statements
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:Describe*",
          "logs:Get*",
          "logs:List*",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsCreateTagged"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:TagLogGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "CloudWatchLogsManageProjectResources"
        Effect = "Allow"
        Action = [
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:UntagLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutSubscriptionFilter",
          "logs:DeleteSubscriptionFilter"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "CloudWatchLogsManageDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies"
        ]
        Resource = "*"
      },
      # SQS Statements
      {
        Sid    = "SQSRead"
        Effect = "Allow"
        Action = [
          "sqs:List*",
          "sqs:Get*"
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
        Sid    = "SQSManageProjectResources"
        Effect = "Allow"
        Action = [
          "sqs:DeleteQueue",
          "sqs:SetQueueAttributes",
          "sqs:UntagQueue",
          "sqs:AddPermission",
          "sqs:RemovePermission",
          "sqs:PurgeQueue"
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
}
