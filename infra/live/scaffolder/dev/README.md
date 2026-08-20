# Scaffolder — dev

Everything the scaffolder service owns in AWS: its DynamoDB table, its Step
Functions task queue and DLQ, the IRSA role its pod assumes, and the annotated
ServiceAccount that binds the two.

The service itself runs as a container on the EKS cluster the `api` component
creates — see [ADR-0004](../../../../docs/adr/0004-scaffolder-runs-as-a-container-on-eks.md)
for why it is not on Lambda, and `services/scaffolder/CLAUDE.md` for the service.

## Dependencies

Apply order is `api` → `scaffolder`. This stack reads the cluster's coordinates
and OIDC provider from SSM (`/idp/shared/eks/*`), published by
`infra/live/provisioner_api/dev/eks_ssm.tf`. There is no `terraform_remote_state`
read, so this workspace needs no access to the api workspace's state.

## What is deliberately not here

- **The scaffold state machine.** It orchestrates the Infra Worker as well as
  this service, so it is shared infrastructure and belongs in its own component
  once the Infra Worker exists. It will target `task_queue_arn` from this stack.
- **The template S3 bucket, its KMS key, and the GitHub App secret.** Not built
  yet. They belong here when they are.

## Usage

```bash
terraform init
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

Or through the pipeline: `ops-infra-component.yml` with component `scaffolder`.
