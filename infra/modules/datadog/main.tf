data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Datadog AWS Integration. Created BEFORE the IAM role: it references the role
# only by name (a plain string), and Datadog responds with the External ID it
# will present when assuming that role. The role's trust policy is then built
# from that generated ID — a role created first with a self-chosen ID would
# reject Datadog's AssumeRole calls.
resource "datadog_integration_aws_account" "this" {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_partition  = data.aws_partition.current.partition

  aws_regions {
    include_only = [var.aws_region]
  }

  auth_config {
    aws_auth_config_role {
      role_name = var.role_name
    }
  }

  # Log collection via the Datadog Lambda forwarder is retired — logs now reach
  # Datadog through the OTel Collector's `datadog` exporter. The provider still
  # requires this block, so keep it with no forwarder configured.
  logs_config {
    lambda_forwarder {
      lambdas = []
      sources = []
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
        "AWS/ApiGateway",
        "AWS/ApplicationELB",
        "AWS/AutoScaling",
        "AWS/Cognito",
        "AWS/DynamoDB",
        "AWS/EC2",
        "AWS/ELB",
        "AWS/Lambda",
        "AWS/NetworkELB",
        "AWS/RDS",
        "AWS/S3",
        "AWS/SNS",
        "AWS/SQS",
        "AWS/Usage"
      ]
    }
  }

  # extended_collection populates Datadog's Resource Catalog. It additionally
  # needs the SecurityAudit managed policy, attached in the aws_integration
  # module.
  resources_config {
    cloud_security_posture_management_collection = false
    extended_collection                          = true
  }
}

# IAM role Datadog assumes to crawl the account. Its trust policy pins
# sts:ExternalId to the Datadog-generated value exported by the integration
# resource above.
module "aws_integration" {
  source = "../aws/datadog_integration"

  role_name   = var.role_name
  external_id = datadog_integration_aws_account.this.auth_config.aws_auth_config_role.external_id
  environment = var.environment
  project     = var.project
}
