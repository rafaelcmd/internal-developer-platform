module "eks" {
  source = "../../../modules/aws/eks"

  # Infrastructure dependencies — sourced from SSM (published by shared/vpc)
  vpc_id             = data.aws_ssm_parameter.vpc_id.value
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)

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

  # AWS Load Balancer Controller (reconciles TargetGroupBinding for pod -> TG
  # registration; NLB/TG are Terraform-managed in this stack).
  install_aws_load_balancer_controller       = true
  aws_load_balancer_controller_chart_version = var.aws_load_balancer_controller_chart_version

  # Datadog Cluster Agent (cluster-level visibility on Fargate — pod inventory,
  # orchestrator explorer, kube-state-metrics). DD_API_KEY is read from the SSM
  # parameter that already exists for the Lambda forwarder.
  install_datadog_cluster_agent = true
  datadog_chart_version         = var.datadog_chart_version
  datadog_api_key               = data.aws_ssm_parameter.datadog_api_key.value

  # Fargate pod log routing — managed Fluent Bit ships pod stdout to a single
  # CloudWatch log group that we subscribe to the Datadog Lambda forwarder
  # below. Removes the need for a per-pod log-collection sidecar.
  enable_fargate_logging     = true
  fargate_log_retention_days = var.cluster_log_retention_days

  # Operator IAM principals granted cluster-admin so kubectl works from their workstations.
  cluster_admin_principal_arns = var.cluster_admin_principal_arns

  tags = local.tags
}

module "sqs" {
  source = "../../../modules/aws/sqs"

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
# API NLB (TERRAFORM-MANAGED)
# Kubernetes binds API pods to this target group via TargetGroupBinding.
# =============================================================================

module "api_nlb" {
  source = "../../../modules/aws/nlb"

  nlb_name           = var.api_nlb_name
  internal           = true
  load_balancer_type = "network"
  subnets            = split(",", data.aws_ssm_parameter.private_subnet_ids.value)

  target_group_name     = var.api_target_group_name
  target_group_port     = var.api_target_group_port
  target_group_protocol = "TCP"
  vpc_id                = data.aws_ssm_parameter.vpc_id.value
  target_type           = "ip"

  health_check_enabled  = true
  health_check_protocol = "HTTP"
  health_check_port     = tostring(var.api_target_group_port)
  health_check_path     = var.api_target_group_health_check_path
  health_check_interval = 30
  health_check_timeout  = 6
  healthy_threshold     = 3
  unhealthy_threshold   = 3

  listener_port     = var.api_nlb_listener_port
  listener_protocol = "TCP"

  project     = var.project
  environment = var.environment
  tags        = local.tags
}

resource "aws_ssm_parameter" "api_nlb_arn" {
  name  = var.api_nlb_arn_ssm_parameter_name
  type  = "String"
  value = module.api_nlb.nlb_arn

  tags = local.tags
}

resource "aws_ssm_parameter" "api_nlb_dns" {
  name  = var.api_nlb_dns_ssm_parameter_name
  type  = "String"
  value = module.api_nlb.nlb_dns_name

  tags = local.tags
}

resource "aws_ssm_parameter" "api_target_group_arn" {
  name  = var.api_target_group_arn_ssm_parameter_name
  type  = "String"
  value = module.api_nlb.target_group_arn

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
  source = "../../../modules/aws/lambda"

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
