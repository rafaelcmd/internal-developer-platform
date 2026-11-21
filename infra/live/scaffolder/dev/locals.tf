locals {
  # The IAM path this component's pipeline may manage. Roles and policies
  # outside it are out of that pipeline's reach. See docs/adr/0009.
  iam_path = "/idp/workload/scaffolder/"

  tags = {
    Environment = var.environment
    Project     = var.project
    Service     = var.service_name
  }

  name_prefix = "${var.project}-${var.service_name}"

  worker_role_names = {
    for worker in keys(local.workers) :
    worker => "${local.name_prefix}-${worker}-${var.environment}"
  }

  # Built from the name and path rather than read from module.worker_irsa: the
  # worker's policy references the secret, so taking the ARN from the role would
  # make the secret and the role depend on each other. A check in irsa.tf fails
  # the plan if the two drift.
  github_app_key_reader_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role${local.iam_path}${local.worker_role_names["github"]}"

  # One container image, two Deployments, two IAM roles.
  #
  # The property this buys: nothing that runs name reservations can read the
  # GitHub App private key. A bug, a compromised dependency or a hostile task
  # payload in the state worker cannot reach the credential that can create and
  # write to repositories across the organisation.
  #
  # Each worker needs its own queue for this to hold. Two pods polling one queue
  # would each receive tasks meant for the other, and the IAM split would then
  # surface as AccessDenied at random rather than as a boundary. Routing has to
  # match the trust boundary.
  #
  # See docs/adr/0004-scaffolder-runs-as-a-container-on-eks.md for why the
  # service is a container rather than a set of Lambda functions.
  workers = {
    state = {
      description          = "name reservations and other state-only tasks"
      reads_github_app_key = false
    }
    github = {
      description          = "repository creation and everything else that talks to GitHub"
      reads_github_app_key = true
    }
  }
}
