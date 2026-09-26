# The provisioner's IAM role and the ServiceAccount its Deployment binds to, in
# k8s/provisioner/deployment.yaml.
#
# The queue it reads and the cluster it runs on belong to the api component, and
# it reaches both by name through SSM. The state machine it starts and the table
# it records requests in belong to this stack. A permission the consumer needs
# is added here rather than in the stack that happens to own the cluster.

data "aws_iam_policy_document" "provisioner" {
  # The consumer resolves the queue URL from
  # /INTERNAL_DEVELOPER_PLATFORM/PROVISIONER_QUEUE_URL at startup.
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/INTERNAL_DEVELOPER_PLATFORM/*",
    ]
  }

  # The consume side of the provisioning queue. The API holds the send side, in
  # live/api/dev/irsa.tf.
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [data.aws_ssm_parameter.provisioner_queue_arn.value]
  }

  # Starting a scaffold execution, and reading one back. StartExecution is the
  # only way into the workflow; the consumer has no permission to influence an
  # execution once it is running, which stays with the workers holding tokens.
  statement {
    sid       = "StartScaffoldExecutions"
    actions   = ["states:StartExecution"]
    resources = [module.state_machine.state_machine_arn]
  }

  statement {
    sid     = "ReadScaffoldExecutions"
    actions = ["states:DescribeExecution"]

    # Execution ARNs extend the state machine ARN under a different resource
    # type, so the grant cannot be written against the machine ARN itself.
    resources = [
      "${replace(module.state_machine.state_machine_arn, ":stateMachine:", ":execution:")}:*",
    ]
  }

  # Request state, read only. The state machine is the single writer of a
  # request row, so the two never race over it, and a redelivered message is
  # recognised by the deterministic execution name rather than by this table.
  statement {
    sid       = "ReadRequestState"
    actions   = ["dynamodb:GetItem"]
    resources = [module.requests.table_arn]
  }
}

module "irsa" {
  source = "../../../modules/aws/irsa"

  role_name          = "${var.cluster_name}-provisioner"
  policy_description = "Permissions for the internal-developer-platform provisioner pod"
  policy_json        = data.aws_iam_policy_document.provisioner.json

  oidc_provider_arn = data.aws_ssm_parameter.eks_oidc_provider_arn.value
  oidc_provider_url = data.aws_ssm_parameter.eks_oidc_provider_url.value

  namespace            = local.service_account_namespace
  service_account_name = local.service_account_name

  tags = local.tags
}
