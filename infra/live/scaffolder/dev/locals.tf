locals {
  tags = {
    Environment = var.environment
    Project     = var.project
    Service     = var.service_name
  }

  name_prefix = "${var.project}-${var.service_name}"
}
