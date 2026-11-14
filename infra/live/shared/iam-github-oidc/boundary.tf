# The permissions boundary every workload role carries: the IRSA roles of the
# platform's pods and EKS add-ons, the Fargate pod execution role and the Step
# Functions execution role. Pipelines may create and change those roles only
# while this boundary is attached, so a pipeline cannot mint a role more
# powerful than a workload needs. See docs/adr/0009.

data "aws_iam_policy_document" "workload_boundary" {
  # The services the platform's workloads call. Service-level wildcards are
  # acceptable here because the boundary only caps; each role's own policy is
  # what grants, scoped to concrete ARNs.
  statement {
    sid = "WorkloadServices"
    actions = [
      "sqs:*",
      "states:SendTaskSuccess",
      "states:SendTaskFailure",
      "states:SendTaskHeartbeat",
      "states:StartExecution",
      "states:DescribeExecution",
      "dynamodb:*",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "cognito-idp:*",
      "logs:*",
      "xray:*",
      "cloudwatch:*",
      "aps:RemoteWrite",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }

  # The AWS Load Balancer Controller manages NLBs, target groups, security
  # groups and WAF associations on the cluster's behalf.
  statement {
    sid = "LoadBalancerController"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "waf-regional:*",
      "wafv2:*",
      "shield:*",
      "tag:GetResources",
      "tag:TagResources",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "LoadBalancingServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  # Nothing above allows these, so they are already implicitly denied. The
  # explicit deny keeps that true if an Allow above is ever widened, because a
  # deny in a boundary overrides any Allow in the role's own policies.
  statement {
    sid    = "DenyIdentityAndAccountAdministration"
    effect = "Deny"
    actions = [
      "iam:Add*",
      "iam:Attach*",
      "iam:CreateAccessKey",
      "iam:CreateGroup",
      "iam:CreateInstanceProfile",
      "iam:CreateLoginProfile",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreatePolicy*",
      "iam:CreateRole",
      "iam:CreateSAMLProvider",
      "iam:CreateUser",
      "iam:Delete*",
      "iam:Detach*",
      "iam:PassRole",
      "iam:Put*",
      "iam:Remove*",
      "iam:Set*",
      "iam:Tag*",
      "iam:Untag*",
      "iam:Update*",
      "iam:Upload*",
      "sts:AssumeRole",
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "${var.project}-${var.environment}-workload-boundary"
  path        = local.boundary_path
  description = "Maximum permissions of any workload role a pipeline creates"
  policy      = data.aws_iam_policy_document.workload_boundary.json

  tags = local.tags
}

# Component stacks read the ARN from here to attach the boundary to their roles.
# The pipeline grants pin the ARN itself rather than trusting this parameter, so
# rewriting it can only make an apply fail.
resource "aws_ssm_parameter" "workload_boundary_arn" {
  name        = "/idp/shared/iam/workload_boundary_arn"
  description = "Permissions boundary every workload role must carry"
  type        = "String"
  value       = aws_iam_policy.workload_boundary.arn

  tags = local.tags
}
