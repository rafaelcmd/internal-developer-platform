# IAM grants of the CI role for the api component (live/api/dev), split from
# policy_api.tf because together they exceed the size limit of one managed
# policy. IAM is reachable in three shapes: workload roles under
# /idp/workload/api/ with the workload boundary (local.workload_iam_statements),
# the Fargate pod execution role by name with the same boundary, and the
# cluster role by name with AmazonEKSClusterPolicy as the only policy it may
# hold. See docs/adr/0009.

resource "aws_iam_policy" "pipeline_api_iam" {
  name        = "${var.project}-${var.environment}-pipeline-api-iam-policy"
  description = "Pipeline policy for the api stack (IRSA, cluster and Fargate roles)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      # Only the cluster's own issuer. The GitHub provider sits outside this
      # pattern, so this pipeline cannot rewrite the trust anchor CI runs on.
      {
        Sid    = "IAMOpenIDConnectProviderForIRSA"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider"
        ]
        Resource = "arn:aws:iam::${local.account_id}:oidc-provider/oidc.eks.*"
      },
      {
        Sid    = "FargateRoleWithinBoundary"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePermissionsBoundary",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = local.eks_fargate_role_arn
        Condition = {
          StringEquals = {
            "iam:PermissionsBoundary" = local.workload_boundary_arn
          }
        }
      },
      # The cluster role holds AWS-managed permissions only, so the policy
      # attached is pinned instead of a boundary. Neither role is granted
      # inline policies.
      {
        Sid    = "ClusterRoleManagedPolicyOnly"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = local.eks_cluster_role_arn
        Condition = {
          ArnEquals = {
            "iam:PolicyARN" = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
          }
        }
      },
      # CreateRole carries no iam:PolicyARN, so it cannot share the statement
      # above. A cluster role created here holds nothing until that statement
      # attaches the one policy it allows.
      {
        Sid      = "ClusterRoleCreate"
        Effect   = "Allow"
        Action   = "iam:CreateRole"
        Resource = local.eks_cluster_role_arn
      },
      {
        Sid    = "ClusterAndFargateRoleLifecycle"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = [
          local.eks_cluster_role_arn,
          local.eks_fargate_role_arn
        ]
      },
      {
        Sid      = "IAMServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:aws:iam::${local.account_id}:role/aws-service-role/*"
      },
      {
        Sid    = "IAMPassRoleToClusterServices"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          local.eks_cluster_role_arn,
          local.eks_fargate_role_arn
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "eks.amazonaws.com",
              "eks-fargate-pods.amazonaws.com"
            ]
          }
        }
      }
    ], local.workload_iam_statements["api"])
  })

  tags = local.tags
}

locals {
  eks_cluster_role_arn = "arn:aws:iam::${local.account_id}:role/${var.eks_cluster_name}-cluster-role"
  eks_fargate_role_arn = "arn:aws:iam::${local.account_id}:role/${var.eks_cluster_name}-fargate-role"
}
