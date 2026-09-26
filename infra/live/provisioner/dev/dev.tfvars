project      = "internal-developer-platform"
environment  = "dev"
aws_region   = "us-east-1"
service_name = "provisioner"

cluster_name = "internal-developer-platform-cluster"

# dev is disposable: the stack is torn down and rebuilt by ops-platform-down /
# ops-platform-up. A longer-lived environment must turn both of these on.
point_in_time_recovery_enabled = false
deletion_protection_enabled    = false

# No infra worker is deployed yet, so the state machine's infrastructure branch
# fails a request that asks for cloud resources instead of silently skipping it.
# Set this to the worker's queue name when that service exists.
infra_worker_task_queue_name = null
