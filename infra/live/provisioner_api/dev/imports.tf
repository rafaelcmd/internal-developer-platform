# =============================================================================
# IMPORT BLOCKS — auto-adopt orphaned resources during destroy/recreate cycles
# =============================================================================

# The Datadog forwarder Lambda's basic execution role grants
# logs:CreateLogGroup. Between `terraform destroy` of the log-group resource
# and `terraform destroy` of the Lambda function, a still-running invocation
# can auto-recreate the group. On the next apply, plain create would fail
# with ResourceAlreadyExistsException. This block tells Terraform: if it's
# already there, adopt it into state and reconcile; if not, create normally.
import {
  to = module.datadog_forwarder.aws_cloudwatch_log_group.lambda_logs
  id = "/aws/lambda/provisioner-api-datadog-forwarder"
}
