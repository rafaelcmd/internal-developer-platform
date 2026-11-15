# Workload deploy workflows (api, provisioner, otel-collector, redis).
# These run no Terraform: they read a handful of SSM parameters, push images,
# and apply Kubernetes manifests. Cluster authorization is separate: the role
# also needs an entry in access_entries (live/api/dev/dev.tfvars), which scopes
# its kubectl access to the namespaces it deploys to.

resource "aws_iam_policy" "pipeline_deploy" {
  name        = "${var.project}-${var.environment}-pipeline-deploy-policy"
  description = "Pipeline policy for workload deploys (SSM reads, ECR push, cluster auth)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDeployParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = local.project_parameter_arns
      },
      # GetAuthorizationToken takes no resource, so it cannot share the
      # repository-scoped statement below.
      {
        Sid      = "ECRLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushWorkloadImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:*:${local.account_id}:repository/${var.project}*"
      },
      {
        Sid      = "ClusterAuthForKubectl"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:aws:eks:*:${local.account_id}:cluster/${var.project}-*"
      }
    ]
  })

  tags = local.tags
}
