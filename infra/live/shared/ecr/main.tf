module "ecr" {
  source = "git::https://github.com/rafaelcmd/cloud-ops-manager.git//infra/modules/aws/ecr?ref=main"

  repository_name = "cloudops-manager-repo"
}
