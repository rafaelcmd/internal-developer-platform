module "ecr" {
  source = "git::https://github.com/rafaelcmd/internal-developer-platform.git//infra/modules/aws/ecr?ref=main"

  repository_name = "internal-developer-platform-repo"
}
