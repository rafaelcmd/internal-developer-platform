terraform {
  cloud {
    organization = "internal-developer-platform-org"

    workspaces {
      name = "internal-developer-platform-infra-worker-aws-dev"
    }
  }
}
