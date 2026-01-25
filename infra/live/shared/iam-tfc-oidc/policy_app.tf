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
        Sid      = "IAMPassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = [
              "ecs-tasks.amazonaws.com",
              "lambda.amazonaws.com",
              "apigateway.amazonaws.com"
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
      # API Gateway Statements (REST API)
      {
        Sid    = "APIGatewayRead"
        Effect = "Allow"
        Action = "apigateway:GET"
        Resource = "*"
      },
      {
        Sid    = "APIGatewayWrite"
        Effect = "Allow"
        Action = [
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:PATCH",
          "apigateway:DELETE",
          "apigateway:TagResource",
          "apigateway:UntagResource"
        ]
        Resource = "*"
      },
      # EC2 permissions for REST API VPC Link (uses VPC Endpoint Services)
      {
        Sid    = "EC2VPCLinkPermissions"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpcEndpointServiceConfiguration",
          "ec2:DeleteVpcEndpointServiceConfigurations",
          "ec2:DescribeVpcEndpointServiceConfigurations",
          "ec2:ModifyVpcEndpointServiceConfiguration",
          "ec2:ModifyVpcEndpointServicePermissions",
          "ec2:DescribeVpcEndpointServicePermissions",
          "ec2:DescribeVpcEndpointServices"
        ]
        Resource = "*"
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
      },
      # WAFv2 Statements
      {
        Sid    = "WAFv2Read"
        Effect = "Allow"
        Action = [
          "wafv2:List*",
          "wafv2:Get*",
          "wafv2:Describe*"
        ]
        Resource = "*"
      },
      {
        Sid    = "WAFv2ManagedRules"
        Effect = "Allow"
        Action = [
          "wafv2:CreateWebACL",
          "wafv2:UpdateWebACL"
        ]
        Resource = [
          "arn:aws:wafv2:*:*:regional/managedruleset/*/*"
        ]
      },
      {
        Sid    = "WAFv2CreateTagged"
        Effect = "Allow"
        Action = [
          "wafv2:CreateWebACL",
          "wafv2:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "WAFv2ManageProjectResources"
        Effect = "Allow"
        Action = [
          "wafv2:DeleteWebACL",
          "wafv2:UpdateWebACL",
          "wafv2:UntagResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "wafv2:PutLoggingConfiguration",
          "wafv2:DeleteLoggingConfiguration"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "WAFv2AssociateWebACL"
        Effect = "Allow"
        Action = [
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL"
        ]
        Resource = [
          "arn:aws:wafv2:*:*:regional/webacl/*/*",
          "arn:aws:apigateway:*::/restapis/*",
          "arn:aws:apigateway:*::/restapis/*/stages/*"
        ]
      }
    ]
  })
}
