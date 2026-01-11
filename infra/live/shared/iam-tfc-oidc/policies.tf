resource "aws_iam_policy" "vpc_management" {
  name        = "${var.project}-${var.environment}-vpc-management-policy"
  description = "Least privilege policy for managing VPC resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ViewOnly"
        Effect = "Allow"
        Action = [
          "ec2:Describe*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CreateTaggedResources"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:CreateSubnet",
          "ec2:CreateInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:CreateVpcEndpoint",
          "ec2:AllocateAddress",
          "ec2:CreateTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "VpcActionsRequiringParent"
        Effect = "Allow"
        Action = [
          "ec2:CreateSubnet",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:CreateVpcEndpoint",
          "ec2:CreateNatGateway"
        ]
        Resource = [
          "arn:aws:ec2:*:*:vpc/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:route-table/*",
          "arn:aws:ec2:*:*:elastic-ip/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "ManageProjectResources"
        Effect = "Allow"
        Action = [
          "ec2:DeleteVpc",
          "ec2:ModifyVpcAttribute",
          "ec2:DeleteSubnet",
          "ec2:ModifySubnetAttribute",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:DeleteRouteTable",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:ReplaceRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:ReleaseAddress",
          "ec2:DisassociateAddress",
          "ec2:DeleteNatGateway",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:DeleteVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:ModifyVpcEndpoint",
          "ec2:CreateTags",
          "ec2:DeleteTags"
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

resource "aws_iam_policy" "iam_management" {
  name        = "${var.project}-${var.environment}-iam-management-policy"
  description = "Least privilege policy for managing IAM resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMRead"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMServiceLinkedRole"
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-service-role/*"
      },
      {
        Sid    = "IAMWrite"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "IAMManageExisting"
        Effect = "Allow"
        Action = [
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider"
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

resource "aws_iam_policy" "ecr_management" {
  name        = "${var.project}-${var.environment}-ecr-management-policy"
  description = "Least privilege policy for managing ECR resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:ListTagsForResource",
          "ecr:GetLifecyclePolicy",
          "ecr:GetRepositoryPolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      },
      {
        Sid    = "CreateTaggedRepository"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "ManageProjectRepository"
        Effect = "Allow"
        Action = [
          "ecr:DeleteRepository",
          "ecr:PutLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:StartLifecyclePolicyPreview",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:PutImageScanningConfiguration",
          "ecr:UntagResource"
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

resource "aws_iam_policy" "cognito_management" {
  name        = "${var.project}-${var.environment}-cognito-management-policy"
  description = "Least privilege policy for managing Cognito resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CognitoRead"
        Effect = "Allow"
        Action = [
          "cognito-idp:List*",
          "cognito-idp:Describe*",
          "cognito-idp:Get*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CognitoCreateTagged"
        Effect = "Allow"
        Action = [
          "cognito-idp:CreateUserPool",
          "cognito-idp:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "CognitoManageProjectResources"
        Effect = "Allow"
        Action = [
          "cognito-idp:DeleteUserPool",
          "cognito-idp:UpdateUserPool",
          "cognito-idp:CreateUserPoolClient",
          "cognito-idp:DeleteUserPoolClient",
          "cognito-idp:UpdateUserPoolClient",
          "cognito-idp:CreateGroup",
          "cognito-idp:DeleteGroup",
          "cognito-idp:UpdateGroup",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:CreateUserPoolDomain",
          "cognito-idp:DeleteUserPoolDomain",
          "cognito-idp:UntagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      {
         Sid = "SSMParameterManagement"
         Effect = "Allow"
         Action = [
            "ssm:PutParameter",
            "ssm:DeleteParameter",
            "ssm:GetParameter",
            "ssm:GetParameters",
            "ssm:AddTagsToResource",
            "ssm:RemoveTagsFromResource"
         ]
         Resource = "arn:aws:ssm:*:*:parameter/*"
         Condition = {
            StringEquals = {
               "aws:ResourceTag/Project" = var.project
            }
         }
      },
      {
        Sid = "SSMParameterCreate"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:AddTagsToResource"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_management" {
  name        = "${var.project}-${var.environment}-ecs-management-policy"
  description = "Least privilege policy for managing ECS resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "ecs:DeregisterTaskDefinition",
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
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
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

resource "aws_iam_policy" "api_gateway_management" {
  name        = "${var.project}-${var.environment}-api-gateway-management-policy"
  description = "Least privilege policy for managing API Gateway resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "APIGatewayRead"
        Effect = "Allow"
        Action = [
          "apigateway:GET"
        ]
        Resource = "*"
      },
      {
        Sid    = "APIGatewayCreateTagged"
        Effect = "Allow"
        Action = [
          "apigateway:POST",
          "apigateway:TagResource"
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
          "apigateway:UntagResource"
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

resource "aws_iam_policy" "lambda_management" {
  name        = "${var.project}-${var.environment}-lambda-management-policy"
  description = "Least privilege policy for managing Lambda resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
      {
        Sid    = "IAMPassRoleLambda"
        Effect = "Allow"
        Action = "iam:PassRole"
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

resource "aws_iam_policy" "nlb_management" {
  name        = "${var.project}-${var.environment}-nlb-management-policy"
  description = "Least privilege policy for managing NLB resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "NLBRead"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:Describe*"
        ]
        Resource = "*"
      },
      {
        Sid    = "NLBCreateTagged"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:AddTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "NLBManageProjectResources"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:SetSecurityGroups"
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

resource "aws_iam_policy" "sqs_management" {
  name        = "${var.project}-${var.environment}-sqs-management-policy"
  description = "Least privilege policy for managing SQS resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

resource "aws_iam_policy" "ssm_management" {
  name        = "${var.project}-${var.environment}-ssm-management-policy"
  description = "Least privilege policy for managing SSM Parameter Store resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMCreateTagged"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:AddTagsToResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "SSMManageProjectResources"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:DeleteParameters",
          "ssm:RemoveTagsFromResource",
          "ssm:AddTagsToResource" 
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

resource "aws_iam_policy" "ssm_management" {
  name        = "${var.project}-${var.environment}-ssm-management-policy"
  description = "Least privilege policy for managing SSM Parameter Store resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMCreateTagged"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:AddTagsToResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "SSMManageProjectResources"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:DeleteParameters",
          "ssm:RemoveTagsFromResource",
          "ssm:AddTagsToResource" 
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
