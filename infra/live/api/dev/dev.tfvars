project      = "internal-developer-platform"
environment  = "dev"
aws_region   = "us-east-1"
service_name = "resource-provisioner-api"
app_version  = "1.0.0"

# EKS cluster
cluster_name                               = "internal-developer-platform-cluster"
cluster_version                            = "1.34"
cluster_endpoint_public_access             = true
cluster_public_access_cidrs                = ["0.0.0.0/0"]
fargate_namespaces                         = ["default", "kube-system", "datadog"]
cluster_log_retention_days                 = 7
aws_load_balancer_controller_chart_version = "1.8.1"
datadog_chart_version                      = "3.227.1"

# Out-of-band alerting destination. SNS topic still gets the alarms even if
# this is left blank; only the auto-created email subscription is skipped.
notification_email = "rafaelcmd@gmail.com"

# IAM principals granted kubectl via EKS Access Entries, for principals that
# need kubectl but never create the cluster: the deploy workflows, the CI roles
# of stacks that create ServiceAccounts here, and operator users working from a
# workstation.
#
# Never list whoever applies this stack. bootstrap_cluster_creator_admin_permissions
# already grants the creator an access entry, and creating a second one for the
# same principal fails the apply with ResourceInUseException. That excludes
# github-actions-tf-api, which is the creator on every CI-applied cluster; it
# would equally exclude the operator user on a cluster applied from a laptop.
#
# Only the operator holds cluster admin. Every pipeline principal gets
# AmazonEKSEditPolicy confined to the namespaces it writes to:
#   - github-actions-deploy applies the workload manifests in default and
#     observability. The kubernetes group, which must match the eks module's
#     target_group_binding_editor_group output, adds the API's
#     TargetGroupBinding, a CRD the Edit policy does not cover.
#   - github-actions-tf-scaffolder, -provisioner and -infra-worker-aws create
#     the ServiceAccounts their pods bind to, all in default. Without an entry
#     their kubernetes provider fails with a bare "Unauthorized".
access_entries = [
  {
    principal_arn = "arn:aws:iam::413703165862:user/rafael"
    access_policy = "AmazonEKSClusterAdminPolicy"
  },
  {
    principal_arn     = "arn:aws:iam::413703165862:role/github-actions-deploy"
    access_policy     = "AmazonEKSEditPolicy"
    namespaces        = ["default", "observability"]
    kubernetes_groups = ["idp:target-group-binding-editors"]
  },
  {
    principal_arn = "arn:aws:iam::413703165862:role/github-actions-tf-scaffolder"
    access_policy = "AmazonEKSEditPolicy"
    namespaces    = ["default"]
  },
  {
    principal_arn = "arn:aws:iam::413703165862:role/github-actions-tf-provisioner"
    access_policy = "AmazonEKSEditPolicy"
    namespaces    = ["default"]
  },
  {
    principal_arn = "arn:aws:iam::413703165862:role/github-actions-tf-infra-worker-aws"
    access_policy = "AmazonEKSEditPolicy"
    namespaces    = ["default"]
  },
]

# Terraform-managed API NLB + target group consumed by API Gateway and
# k8s TargetGroupBinding.
api_nlb_name                            = "idp-api-nlb"
api_target_group_name                   = "idp-api-tg"
api_nlb_listener_port                   = 80
api_target_group_port                   = 8080
api_target_group_health_check_path      = "/v1/health"
api_nlb_arn_ssm_parameter_name          = "/internal-developer-platform/provisioner-api/nlb/arn"
api_nlb_dns_ssm_parameter_name          = "/internal-developer-platform/provisioner-api/nlb/dns_name"
api_target_group_arn_ssm_parameter_name = "/internal-developer-platform/provisioner-api/nlb/target_group_arn"

queue_name                = "provisioner_queue"
delay_seconds             = 0
max_message_size          = 262144
message_retention_seconds = 345600
receive_wait_time_seconds = 20

# Raise this before the provisioner starts doing real work per message: it has
# to cover the slowest path through one message, including the Step Functions
# StartExecution calls that will land where the dispatch logging is today.
queue_visibility_timeout_seconds = 60
ssm_parameter_name               = "/INTERNAL_DEVELOPER_PLATFORM/PROVISIONER_QUEUE_URL"
ssm_parameter_type               = "String"

# Redis runs in-cluster (see /k8s/redis/). The SSM parameter publishes the
# service DNS so the API resolves it the same way it did under the ECS module.
redis_ssm_parameter_name = "/INTERNAL_DEVELOPER_PLATFORM/REDIS_ADDR"
redis_endpoint           = "redis.default.svc.cluster.local:6379"
