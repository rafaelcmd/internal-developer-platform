# Local values for better organization and validation
locals {
  enable_log_forwarder = var.datadog_forwarder_arn != null && var.datadog_forwarder_arn != ""
}

# Module for AWS IAM Role
module "aws_integration" {
  source = "../aws/datadog_integration"

  role_name   = var.role_name
  external_id = var.external_id
  environment = var.environment
  project     = var.project
}

# Datadog AWS Integration
resource "datadog_integration_aws_account" "this" {
  aws_account_id = module.aws_integration.account_id
  aws_partition  = module.aws_integration.partition

  aws_regions {
    include_only = [var.aws_region]
  }

  auth_config {
    aws_auth_config_role {
      role_name = module.aws_integration.role_name
    }
  }

  logs_config {
    lambda_forwarder {
      lambdas = local.enable_log_forwarder ? [var.datadog_forwarder_arn] : []
      sources = ["s3", "elb", "elbv2", "cloudfront", "redshift", "lambda"]
    }
  }

  traces_config {
    xray_services {
      include_all = true
    }
  }

  metrics_config {
    namespace_filters {
      include_only = [
        "AWS/ECS",
        "AWS/ApplicationELB",
        "AWS/Lambda",
        "AWS/EC2",
        "AWS/RDS",
        "AWS/S3",
        "AWS/SQS",
        "AWS/SNS",
        "AWS/DynamoDB",
        "AWS/ELB",
        "AWS/AutoScaling"
      ]
    }
  }

  resources_config {
    cloud_security_posture_management_collection = false
    extended_collection                          = false
  }

  depends_on = [module.aws_integration]
}
