terraform {
  cloud {
    organization = "internal-developer-platform-org"

    workspaces {
      name = "internal-developer-platform-iam-github-oidc"
    }
  }
}
