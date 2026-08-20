project      = "internal-developer-platform"
environment  = "dev"
aws_region   = "us-east-1"
service_name = "scaffolder"

# dev is disposable: the stack is torn down and rebuilt by ops-platform-down /
# ops-platform-up. A longer-lived environment must turn both of these on.
point_in_time_recovery_enabled = false
deletion_protection_enabled    = false
