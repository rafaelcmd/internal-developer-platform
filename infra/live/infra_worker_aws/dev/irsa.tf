# The AWS infra worker's IAM role and the ServiceAccount its Deployment binds
# to, in k8s/infra-worker-aws/deployment.yaml. The role can consume this
# worker's queue and answer Step Functions callbacks, and nothing else: it
# creates no cloud resources yet, so it holds no provisioning permissions.

data "aws_iam_policy_document" "worker" {
  # GetQueueUrl lets the pod be configured with a queue name rather than an
  # account-qualified URL.
  statement {
    sid = "InfraWorkerTaskQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [module.task_queue.queue_arn]
  }

  # These actions take a task token rather than a resource ARN and support no
  # resource-level permissions, so the wildcard is unavoidable. The grant is
  # inert without a valid token.
  statement {
    sid = "InfraWorkerTaskCallbacks"
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure",
      "states:SendTaskHeartbeat",
    ]
    resources = ["*"]
  }
}

module "irsa" {
  source = "../../../modules/aws/irsa"

  role_name          = "${local.name_prefix}-${var.environment}"
  role_description   = "AWS infra worker: consumes ProvisionInfra tasks and reports them to Step Functions"
  policy_description = "Permissions for the AWS infra worker pod"
  policy_json        = data.aws_iam_policy_document.worker.json

  oidc_provider_arn = data.aws_ssm_parameter.eks_oidc_provider_arn.value
  oidc_provider_url = data.aws_ssm_parameter.eks_oidc_provider_url.value

  namespace            = local.service_account_namespace
  service_account_name = local.service_account_name

  tags = local.tags
}
