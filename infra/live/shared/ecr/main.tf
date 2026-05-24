module "ecr" {
  source = "../../../modules/aws/ecr"

  repository_name = "internal-developer-platform-repo"
  project         = var.project
  environment     = var.environment
}
