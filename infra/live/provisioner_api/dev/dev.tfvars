project      = "internal-developer-platform"
environment  = "dev"
aws_region   = "us-east-1"
service_name = "resource-provisioner-api"
app_version  = "1.0.0"

# EKS cluster
cluster_name                               = "internal-developer-platform-cluster"
cluster_version                            = "1.33"
cluster_endpoint_public_access             = true
cluster_public_access_cidrs                = ["0.0.0.0/0"]
fargate_namespaces                         = ["default", "kube-system"]
cluster_log_retention_days                 = 7
aws_load_balancer_controller_chart_version = "1.8.1"

# IAM principals granted cluster-admin via EKS Access Entries. Replace the
# placeholder with the output of `aws sts get-caller-identity` on your workstation.
cluster_admin_principal_arns = [
  "arn:aws:iam::413703165862:user/rafael",
  "arn:aws:iam::413703165862:role/github-actions-oidc-role",
]

lambda_function_name              = "provisioner-api-datadog-forwarder"
lambda_runtime                    = "python3.9"
lambda_timeout                    = 120
lambda_memory_size                = 1024
archive_type                      = "zip"
archive_output_path_prefix        = "."
iam_role_name_suffix              = "-role"
lambda_basic_execution_policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
additional_policy_name_suffix     = "-additional-policy"
permission_statement_id           = "AllowExecutionFromCloudWatchLogs"
permission_action                 = "lambda:InvokeFunction"
permission_principal              = "logs.amazonaws.com"
log_group_name_prefix             = "/aws/lambda"

queue_name                = "provisioner_queue"
delay_seconds             = 0
max_message_size          = 262144
message_retention_seconds = 345600
receive_wait_time_seconds = 20
ssm_parameter_name        = "/INTERNAL_DEVELOPER_PLATFORM/PROVISIONER_QUEUE_URL"
ssm_parameter_type        = "String"

# Redis runs in-cluster (see /k8s/redis/). The SSM parameter publishes the
# service DNS so the API resolves it the same way it did under the ECS module.
redis_ssm_parameter_name = "/INTERNAL_DEVELOPER_PLATFORM/REDIS_ADDR"
redis_endpoint           = "redis.default.svc.cluster.local:6379"
