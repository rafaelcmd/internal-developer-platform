# Baseline attached to every per-component pipeline role.
#
# Two things every stack needs regardless of what it provisions: read access
# for Terraform's state refresh and data sources, and SSM parameter access.
# Stacks are decoupled through SSM rather than remote state, so each one reads
# the parameters its producers published and writes its own.
#
# It also holds the explicit denies every pipeline role shares. A deny overrides
# any Allow in the component policies, so these hold even where a component
# grant is broader than intended. See docs/adr/0009.

resource "aws_iam_policy" "pipeline_common" {
  name        = "${var.project}-${var.environment}-pipeline-common-policy"
  description = "Read-only describes plus SSM parameter access shared by every pipeline role"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeForRefreshAndDataSources"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "iam:Get*",
          "iam:List*",
          "kms:Describe*",
          "kms:List*",
          "tag:GetResources"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath",
          "ssm:ListTagsForResource"
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
        Resource = local.project_parameter_arns
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "SSMManageProjectParameters"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:DeleteParameters",
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource"
        ]
        Resource = local.project_parameter_arns
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      # Pipeline credentials come from GitHub's OIDC token and never need to
      # chain into another role. Denying the call means a role whose trust a
      # pipeline rewrote still cannot be assumed by that pipeline.
      {
        Sid      = "DenyRoleChaining"
        Effect   = "Deny"
        Action   = "sts:AssumeRole"
        Resource = "*"
      },
      # Deny with NotAction: everything except reads is denied on the
      # identities CI runs as and on the policies only this stack may change.
      # Without it a pipeline could attach a policy to its own role or relax its
      # own trust.
      {
        Sid       = "DenyChangingPipelineIdentities"
        Effect    = "Deny"
        NotAction = ["iam:Get*", "iam:List*"]
        Resource = [
          "arn:aws:iam::${local.account_id}:role/github-actions-*",
          module.github_actions_oidc.oidc_provider_arn,
          "arn:aws:iam::${local.account_id}:policy/${var.project}-${var.environment}-pipeline-*",
          "arn:aws:iam::${local.account_id}:policy${local.boundary_path}*",
          "arn:aws:iam::${local.account_id}:policy${local.integration_policy_path}*"
        ]
      },
      # Component stacks read these to attach the boundary and the Datadog
      # policy. Only this stack writes them.
      {
        Sid    = "DenyChangingIAMParameters"
        Effect = "Deny"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:DeleteParameters",
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource"
        ]
        Resource = "arn:aws:ssm:*:${local.account_id}:parameter/idp/shared/iam/*"
      },
      {
        Sid    = "DenyRemovingPermissionsBoundaries"
        Effect = "Deny"
        Action = [
          "iam:DeleteRolePermissionsBoundary",
          "iam:DeleteUserPermissionsBoundary"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyAttachingAdministrativePolicies"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy",
          "iam:AttachUserPolicy",
          "iam:AttachGroupPolicy"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "iam:PolicyARN" = [
              "arn:aws:iam::aws:policy/AdministratorAccess",
              "arn:aws:iam::aws:policy/IAMFullAccess",
              "arn:aws:iam::aws:policy/PowerUserAccess"
            ]
          }
        }
      },
      # The Project tag decides what the tag-conditioned grants reach, so it may
      # be set only while a resource is created and never removed afterwards.
      # Removing it would let a pipeline orphan another stack's resources from
      # their owner; adding it to an existing resource would bring that
      # resource into reach.
      {
        Sid    = "DenyRemovingProjectTag"
        Effect = "Deny"
        Action = [
          "cloudwatch:UntagResource",
          "cognito-idp:UntagResource",
          "dynamodb:UntagResource",
          "ec2:DeleteTags",
          "ecr:UntagResource",
          "eks:UntagResource",
          "elasticloadbalancing:RemoveTags",
          "iam:UntagOpenIDConnectProvider",
          "iam:UntagPolicy",
          "iam:UntagRole",
          "kms:UntagResource",
          "logs:UntagLogGroup",
          "logs:UntagResource",
          "secretsmanager:UntagResource",
          "sns:UntagResource",
          "sqs:UntagQueue",
          "ssm:RemoveTagsFromResource",
          "states:UntagResource",
          "wafv2:UntagResource"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:TagKeys" = ["Project"]
          }
        }
      },
      # EC2 is the one service that says whether a tag call is part of a
      # create: ec2:CreateAction is present only then. A standalone CreateTags
      # carrying Project is retagging an existing resource.
      {
        Sid      = "DenyRetaggingExistingEC2Resources"
        Effect   = "Deny"
        Action   = "ec2:CreateTags"
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:TagKeys" = ["Project"]
          }
          Null = {
            "ec2:CreateAction" = "true"
          }
        }
      }
    ]
  })

  tags = local.tags
}

locals {
  # Every SSM prefix the platform's stacks publish under.
  project_parameter_arns = [
    "arn:aws:ssm:*:${local.account_id}:parameter/idp/*",
    "arn:aws:ssm:*:${local.account_id}:parameter/INTERNAL_DEVELOPER_PLATFORM/*",
    "arn:aws:ssm:*:${local.account_id}:parameter/${var.project}/*"
  ]
}
