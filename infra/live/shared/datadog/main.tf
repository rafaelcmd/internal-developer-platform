module "datadog" {
  source = "../../../modules/datadog"

  aws_region            = var.aws_region
  role_name             = var.role_name
  external_id           = var.external_id
  environment           = var.environment
  project               = var.project
  datadog_forwarder_arn = var.datadog_forwarder_arn
}

resource "aws_ssm_parameter" "datadog_api_key" {
  name        = "/${var.project}/${var.environment}/datadog/api_key"
  description = "Datadog API Key"
  type        = "SecureString"
  value       = var.datadog_api_key

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}
