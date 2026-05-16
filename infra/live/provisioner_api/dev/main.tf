module "eks" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/eks?ref=main"

  # Infrastructure dependencies
  vpc_id             = data.terraform_remote_state.shared_vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.shared_vpc.outputs.private_subnet_ids

  # Project / region
  aws_region  = var.aws_region
  environment = var.environment
  project     = var.project

  # Cluster
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Endpoint access
  endpoint_public_access  = var.cluster_endpoint_public_access
  endpoint_private_access = true
  public_access_cidrs     = var.cluster_public_access_cidrs

  # Pods schedule onto Fargate. The API and Redis live in `default`;
  # kube-system is included so CoreDNS / the LB controller schedule.
  fargate_namespaces = var.fargate_namespaces

  # Control plane logs
  log_retention_days = var.cluster_log_retention_days

  # AWS Load Balancer Controller (provisions the NLB for the API Service)
  install_aws_load_balancer_controller       = true
  aws_load_balancer_controller_chart_version = var.aws_load_balancer_controller_chart_version

  # Operator IAM principals granted cluster-admin so kubectl works from their workstations.
  cluster_admin_principal_arns = var.cluster_admin_principal_arns

  tags = local.tags
}

module "sqs" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/sqs?ref=main"

  # SQS configuration
  queue_name                = var.queue_name
  delay_seconds             = var.delay_seconds
  max_message_size          = var.max_message_size
  message_retention_seconds = var.message_retention_seconds
  receive_wait_time_seconds = var.receive_wait_time_seconds

  # SSM parameter configuration
  ssm_parameter_name = var.ssm_parameter_name
  ssm_parameter_type = var.ssm_parameter_type

  # Common configuration
  project     = var.project
  environment = var.environment

  # Common tags
  tags = local.tags
}

# =============================================================================
# REDIS ENDPOINT SSM PARAMETER
# Redis itself runs as an in-cluster k8s Deployment (see /k8s/redis/), reachable
# via cluster DNS. Publishing the endpoint to SSM keeps the API's runtime config
# identical to the ECS-era contract.
# =============================================================================

resource "aws_ssm_parameter" "redis_endpoint" {
  name  = var.redis_ssm_parameter_name
  type  = "String"
  value = var.redis_endpoint

  tags = local.tags
}

# Datadog Lambda Forwarder for collecting application logs (CloudWatch -> Datadog).
# Application logs now originate from the CloudWatch log group the Datadog agent
# DaemonSet writes to, or from EKS control-plane logs.
module "datadog_forwarder" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/lambda?ref=main"

  # Basic Lambda configuration
  function_name                  = var.lambda_function_name
  source_dir                     = "${path.module}/lambda-src"
  handler                        = "lambda_function.lambda_handler"
  runtime                        = var.lambda_runtime
  timeout                        = var.lambda_timeout
  memory_size                    = var.lambda_memory_size
  reserved_concurrent_executions = -1
  log_retention_days             = 7

  # Archive configuration
  archive_type               = var.archive_type
  archive_output_path_prefix = var.archive_output_path_prefix

  # IAM configuration
  iam_role_name_suffix              = var.iam_role_name_suffix
  assume_role_policy                = var.assume_role_policy
  lambda_basic_execution_policy_arn = var.lambda_basic_execution_policy_arn
  additional_policy_name_suffix     = var.additional_policy_name_suffix

  # Lambda permission configuration
  allow_cloudwatch_logs_invocation = true
  permission_statement_id          = var.permission_statement_id
  permission_action                = var.permission_action
  permission_principal             = var.permission_principal

  # CloudWatch logs configuration
  log_group_name_prefix = var.log_group_name_prefix

  # Environment variables
  environment_variables = {
    DD_API_KEY = data.aws_ssm_parameter.datadog_api_key.value
    DD_SITE    = "datadoghq.com"
    DD_SOURCE  = "aws"
    DD_TAGS    = "env:${var.environment},project:${var.project},service:${var.service_name}"
  }

  # Tags
  tags        = local.tags
  project     = var.project
  environment = var.environment

  # Additional IAM policy for Datadog forwarder
  additional_inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::*/*",
          "arn:aws:s3:::*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}
