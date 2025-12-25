# Provisioner API (dev)

## Layout
- This stack lives at `infra/live/provisioner_api/dev` and consumes reusable modules from `infra/modules/aws/*`.
- State is in Terraform Cloud workspace `internal-developer-platform-provisioner-api-dev`.

## Usage
```sh
cd infra/live/provisioner_api/dev
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

## Files
- backend.tf: Terraform Cloud workspace configuration
- versions.tf: required Terraform and providers
- providers.tf: AWS provider config
- locals.tf: shared tags
- variables.tf: input schema (no env defaults)
- dev.tfvars: environment values for dev
- main.tf: stack composition using local modules
- data.tf: remote states and SSM data
- outputs.tf: stack outputs

## Notes
- Module sources are relative; bump module versions by updating the modules in `infra/modules/aws` or switching paths if you introduce versioned bundles.
- Keep secrets out of tfvars; use SSM/Secrets Manager for sensitive values.
- Prefer `terraform fmt`, `terraform validate`, and linting (tflint/tfsec) before commits.
