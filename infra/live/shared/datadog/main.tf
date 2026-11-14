# The AWS side of the Datadog account integration, plus the API key every
# telemetry component reads.
#
# The key is passed in as a variable and stored as a SecureString. It is the one
# secret this repository's Terraform holds a value for, supplied by CI from the
# DD_API_KEY repository secret rather than committed.

# The integration role's permissions are a policy the bootstrap stack owns, so
# this stack can attach it but not rewrite it. See docs/adr/0009. The ARN is read
# through insecure_value because it becomes a for_each key, which Terraform
# refuses to derive from a value the provider marks sensitive.
data "aws_ssm_parameter" "datadog_integration_policy_arn" {
  name = "/idp/shared/iam/datadog_integration_policy_arn"
}

module "datadog" {
  source = "../../../modules/datadog"

  aws_region              = var.aws_region
  role_name               = var.role_name
  integration_policy_arns = [data.aws_ssm_parameter.datadog_integration_policy_arn.insecure_value]
  environment             = var.environment
  project                 = var.project
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
