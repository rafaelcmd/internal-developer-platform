# AWS Infra Worker — dev

Everything the AWS infra worker owns in AWS: the task queue the scaffold state
machine sends `ProvisionInfra` callbacks to, its dead-letter queue and alarm,
and one IRSA role plus annotated ServiceAccount for the worker pod.

The service is `services/infra-workers/aws`; its Deployment is
`k8s/infra-worker-aws/deployment.yaml`. One infra worker exists per cloud
provider, each with its own queue and identity: see
[ADR-0008](../../../../docs/adr/0008-one-infra-worker-per-cloud-provider.md).

## What the role can do

Consume this queue, and answer Step Functions callbacks
(`SendTaskSuccess`/`SendTaskFailure`/`SendTaskHeartbeat`). The worker logs
tasks and runs no Terraform yet, so the role holds no permission to create
cloud resources. Those are added here when the worker starts provisioning.

## Dependencies

Apply order is `api` → `infra-worker-aws` → `provisioner`.

| Parameter | Published by | Used for |
|---|---|---|
| `/idp/shared/eks/cluster_name`, `/idp/shared/eks/cluster_endpoint`, `/idp/shared/eks/cluster_certificate_authority_data` | `api` | Configuring the kubernetes provider |
| `/idp/shared/eks/oidc_provider_arn`, `/idp/shared/eks/oidc_provider_url` | `api` | The IRSA trust policy |
| `/idp/shared/observability/alerts_topic_arn` | `api` | Where the dead-letter alarm notifies |

It publishes:

| Parameter | Value |
|---|---|
| `/idp/infra-worker-aws/dev/task_queue_name` | The queue name |
| `/idp/infra-worker-aws/dev/task_queue_arn` | The queue ARN |

The provisioner stack targets the queue by name, through
`infra_worker_task_queue_name` in its `dev.tfvars`, so it plans only after this
stack has been applied.

Because it creates a ServiceAccount in a cluster it does not own, its pipeline
role `github-actions-tf-infra-worker-aws` needs an EKS access entry, granted
through `cluster_admin_principal_arns` in `infra/live/api/dev/dev.tfvars`.

## First-time setup

Two things happen outside this stack before its first CI run:

1. Create the Terraform Cloud workspace
   `internal-developer-platform-infra-worker-aws-dev` with execution mode
   **Local** (see `infra/README.md`).
2. Apply `shared/iam-github-oidc`, which creates the
   `github-actions-tf-infra-worker-aws` role the pipeline assumes.

## Usage

```sh
cd infra/live/infra_worker_aws/dev
terraform init
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```
