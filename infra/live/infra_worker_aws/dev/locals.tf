locals {
  # The IAM path this component's pipeline may manage. Roles and policies
  # outside it are out of that pipeline's reach. See docs/adr/0009.
  iam_path = "/idp/workload/infra-worker-aws/"

  tags = {
    Environment = var.environment
    Project     = var.project
    Service     = var.service_name
  }

  name_prefix = "${var.project}-${var.service_name}"

  # Must match serviceAccountName in k8s/infra-worker-aws/deployment.yaml.
  service_account_name      = "internal-developer-platform-infra-worker-aws"
  service_account_namespace = "default"
}
