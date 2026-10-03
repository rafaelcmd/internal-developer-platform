project      = "internal-developer-platform"
environment  = "dev"
aws_region   = "us-east-1"
service_name = "provisioner"

cluster_name = "internal-developer-platform-cluster"

# dev is disposable: the stack is torn down and rebuilt by ops-platform-down /
# ops-platform-up. A longer-lived environment must turn both of these on.
point_in_time_recovery_enabled = false
deletion_protection_enabled    = false

# The AWS infra worker's queue, from infra/live/infra_worker_aws. That stack has
# to be applied first: the data source in data.tf fails the plan otherwise.
infra_worker_task_queue_name = "internal-developer-platform-infra-worker-aws-tasks-dev"

# The scaffolder is not deployed with a GitHub App key in dev yet, so the
# repository states are skipped and an execution runs the infrastructure branch
# alone. Set to true once the scaffolder workers are serving their queues.
scaffold_enabled = false
