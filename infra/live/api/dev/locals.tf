locals {
  # The IAM path this component's pipeline may manage. Roles and policies
  # outside it are out of that pipeline's reach. See docs/adr/0009.
  iam_path = "/idp/workload/api/"

  tags = {
    Environment = var.environment
    Project     = var.project
    Service     = var.service_name
  }
}
