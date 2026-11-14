# The IAM statements every component pipeline that creates workload roles shares,
# rendered once per component so each reaches only its own path. Concatenated
# into the component policies in policy_<component>.tf. See docs/adr/0009.

locals {
  workload_boundary_arn = aws_iam_policy.workload_boundary.arn

  workload_iam_components = ["api", "provisioner", "scaffolder", "infra-worker-aws"]

  workload_role_arns = {
    for c in local.workload_iam_components :
    c => "arn:aws:iam::${local.account_id}:role${local.workload_path_prefix}${c}/*"
  }

  workload_policy_arns = {
    for c in local.workload_iam_components :
    c => "arn:aws:iam::${local.account_id}:policy${local.workload_path_prefix}${c}/*"
  }

  workload_iam_statements = {
    for c in local.workload_iam_components : c => [
      # iam:PermissionsBoundary is the boundary the role has, or is being
      # given. Pinning it on every call that changes what a role may do means a
      # role in this path never holds a policy without the boundary capping it.
      {
        Sid    = "WorkloadRolePermissionsWithinBoundary"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePermissionsBoundary",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy"
        ]
        Resource = local.workload_role_arns[c]
        Condition = {
          StringEquals = {
            "iam:PermissionsBoundary" = local.workload_boundary_arn
          }
        }
      },
      # These calls carry no iam:PermissionsBoundary key, so they cannot share
      # the statement above. None of them changes what the role may do.
      {
        Sid    = "WorkloadRoleLifecycle"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = local.workload_role_arns[c]
      },
      {
        Sid    = "WorkloadManagedPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy"
        ]
        Resource = local.workload_policy_arns[c]
      }
    ]
  }
}
