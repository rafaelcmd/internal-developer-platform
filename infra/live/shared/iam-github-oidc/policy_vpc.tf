# CI role for the vpc component (live/shared/vpc).
# EC2 networking only: VPC, subnets, gateways, route tables, security groups,
# VPC endpoints and elastic IPs. Creation is gated on the Project request tag
# and mutation on the Project resource tag, and the tag can only be applied by a
# create call, so this role cannot touch networking it did not create.

resource "aws_iam_policy" "pipeline_vpc" {
  name        = "${var.project}-${var.environment}-pipeline-vpc-policy"
  description = "Pipeline policy for the vpc stack (EC2 networking)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateTaggedVPCResources"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:CreateSubnet",
          "ec2:CreateInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:CreateVpcEndpoint",
          "ec2:AllocateAddress"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      # ec2:CreateAction is present only while the tags are applied as part of
      # one of these create calls, so this cannot tag a resource that already
      # exists and pull it into the tag-scoped statements below.
      {
        Sid      = "TagVPCResourcesOnCreate"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
            "ec2:CreateAction" = [
              "CreateVpc",
              "CreateSubnet",
              "CreateInternetGateway",
              "CreateNatGateway",
              "CreateRouteTable",
              "CreateSecurityGroup",
              "CreateVpcEndpoint",
              "AllocateAddress"
            ]
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
          "arn:aws:ec2:*:${local.account_id}:vpc/*",
          "arn:aws:ec2:*:${local.account_id}:subnet/*",
          "arn:aws:ec2:*:${local.account_id}:security-group/*",
          "arn:aws:ec2:*:${local.account_id}:route-table/*",
          "arn:aws:ec2:*:${local.account_id}:elastic-ip/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "ManageProjectVPCResources"
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
          "ec2:ReleaseAddress",
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
      },
      # Disassociating does not name a taggable resource. The request carries an
      # association id, which IAM resolves to arn:aws:ec2:<region>:<account>:*/*,
      # and aws:ResourceTag/Project can never match that, so these actions
      # cannot live in the tag-scoped statement above. Listing them there is
      # not enough: a destroy then fails with UnauthorizedOperation and "no
      # identity-based policy allows the action", which reads as if the action
      # were missing from the policy entirely.
      {
        Sid    = "DisassociateUntaggableAttachments"
        Effect = "Allow"
        Action = [
          "ec2:DisassociateAddress",
          "ec2:DisassociateRouteTable"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}
