project      = "internal-developer-platform"
environment  = "dev"
aws_region   = "us-east-1"
service_name = "resource-provisioner-api"
app_version  = "1.0.0"
api_version  = "v1"

# EKS cluster
cluster_name                               = "internal-developer-platform-cluster"
cluster_version                            = "1.30"
cluster_endpoint_public_access             = true
cluster_public_access_cidrs                = ["0.0.0.0/0"]
fargate_namespaces                         = ["default", "kube-system"]
cluster_log_retention_days                 = 7
aws_load_balancer_controller_chart_version = "1.8.1"

# NLB name the AWS Load Balancer Controller will assign. Must match the
# service.beta.kubernetes.io/aws-load-balancer-name annotation in k8s/api/service.yaml.
nlb_name = "idp-api-nlb"

api_gateway_name                 = "internal-developer-platform-api"
api_gateway_description          = "Internal Developer Platform Provisioner API Gateway"
api_gateway_stage_name           = "dev"
api_gateway_auto_deploy          = true
vpc_link_name                    = "internal-developer-platform-vpc-link"
integration_timeout_ms           = 29000
throttle_rate_limit              = 1000
throttle_burst_limit             = 2000
cors_allow_credentials           = false
cors_allow_headers               = ["content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token"]
cors_allow_methods               = ["GET", "POST", "OPTIONS"]
cors_allow_origins               = ["*"]
cors_expose_headers              = []
cors_max_age                     = 86400
api_gateway_log_retention_days   = 7
api_gateway_logging_level        = "INFO"
api_gateway_metrics_enabled      = true
api_gateway_data_trace_enabled   = false
api_gateway_xray_tracing_enabled = true

# WAF Configuration
enable_waf                = true
waf_rate_limit_requests   = 2000
waf_max_request_body_size = 10240
waf_common_rules_excluded = []
waf_enable_logging        = true
waf_log_retention_days    = 7

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
