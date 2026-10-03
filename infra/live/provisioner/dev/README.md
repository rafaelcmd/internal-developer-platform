# Provisioner — dev

The platform's control plane, as infrastructure. Three things:

- **The scaffold state machine** (`state_machine.tf`) — the Step Functions
  workflow that turns one accepted provision request into a repository and the
  cloud resources that go with it. Every worker step is a
  `.waitForTaskToken` callback onto a queue the worker already owns.
- **The request-state table** (`requests.tf`) — one row per request, written
  only by the state machine, holding the execution ARN, the status and the
  outcome. This is the durable answer to "what already happened to request X".
- **The consumer's identity** (`irsa.tf`) — one IAM role assumed through the
  cluster's OIDC provider, and the annotated ServiceAccount its Deployment binds
  to (`k8s/provisioner/deployment.yaml`).

The queue the consumer reads and the cluster it runs on belong to the
[`api`](../../api/dev) component; the task queues the state machine sends to
belong to [`scaffolder`](../../scaffolder/dev) and
[`infra_worker_aws`](../../infra_worker_aws/dev). This stack owns none of them
and reaches each by name.

See [ADR-0006](../../../../docs/adr/0006-step-functions-as-provisioning-orchestrator.md)
for why orchestration is a state machine rather than a loop in the consumer.

## The workflow

```
RecordRequestAccepted  DynamoDB UpdateItem, Status=RUNNING
  └─ ReserveName                          → scaffolder state queue   (callback)
       └─ ScaffoldAndProvision (Parallel)
            ├─ HasDescription → CreateRepository
            │                     → scaffolder github queue          (callback)
            └─ HasResources   → ProvisionInfra
                                  → AWS infra worker queue           (callback)
                               or NoInfrastructureRequested (Pass)
  └─ RecordRequestSucceeded  Status=SUCCEEDED → Succeed
  (Catch from any state) → RecordRequestFailed  Status=FAILED → Fail
```

### `scaffold_enabled`

With `scaffold_enabled = false` (the dev setting while the scaffolder has no
GitHub App key), `ReserveName` and the repository branch are Pass states that
record `{"Skipped": true}`, and `RecordRequestSucceeded` writes no repository
fields. An execution then runs only the infrastructure branch:

```
RecordRequestAccepted → ReserveName (Pass) → ScaffoldAndProvision
    ├─ RepositorySkipped (Pass)
    └─ HasResources → ProvisionInfra → AWS infra worker → SendTaskSuccess
→ RecordRequestSucceeded → RequestSucceeded
```

With it `true` the definition is the full saga above. The scaffolder's queues
are read either way, so its stack must still be applied first.

### Execution input

The machine takes the API's request message unchanged, so the provisioner can
pass through what it consumed rather than translate it:

```json
{
  "request_id": "c0ffee00-...",
  "requested_by": "someone@example.com",
  "application": {
    "name": "payments-api",
    "template": "dotnet-api",
    "owner": "payments",
    "description": "optional"
  },
  "resources": [
    { "name": "payments", "resource_type": "dynamodb_table", "cloud_provider": "aws" }
  ]
}
```

`application.description` and `resources` are the two fields that may be
absent, and each has a Choice state routing around it. Nothing else is
optional: the Amazon States Language fails a state with `States.Runtime` when a
`$.` path does not resolve, and no retry clears that.

The task payloads the machine puts on a queue are PascalCase, matching the
scaffolder's command records and the fixtures in
`services/scaffolder/events/`.

## Running it by hand

The provisioner starts one execution per consumed message, named after its
`request_id`. To start one without going through the API, use the CLI. Every
queue the execution reaches must have a worker polling it or the callback times
out.

```sh
aws stepfunctions start-execution \
  --state-machine-arn "$(terraform output -raw scaffold_state_machine_arn)" \
  --name "req-$(uuidgen)" \
  --input file://execution-input.json

aws dynamodb get-item \
  --table-name "$(terraform output -raw requests_table_name)" \
  --key '{"PK":{"S":"REQUEST#<request_id>"},"SK":{"S":"STATE"}}'
```

## Dependencies

Apply order is `api` → `scaffolder` and `infra-worker-aws` → `provisioner`.
Everything this stack needs arrives through SSM, except the infra worker's queue,
which `dev.tfvars` names directly:

| Parameter | Published by | Used for |
|---|---|---|
| `/idp/shared/eks/cluster_name`, `/idp/shared/eks/cluster_endpoint`, `/idp/shared/eks/cluster_certificate_authority_data` | `api` | Configuring the kubernetes provider, which authenticates per run with `aws eks get-token` |
| `/idp/shared/eks/oidc_provider_arn`, `/idp/shared/eks/oidc_provider_url` | `api` | The IRSA trust policy |
| `/idp/shared/provisioner/queue_arn` | `api` | The resource the consume-side policy is written against |
| `/idp/shared/observability/alerts_topic_arn` | `api` | Where the failed-execution alarm notifies |
| `/idp/scaffolder/dev/state_task_queue_name`, `/idp/scaffolder/dev/github_task_queue_name` | `scaffolder` | The queues the callback states target |
| `infra_worker_task_queue_name` (tfvars) | `infra-worker-aws` | The queue `ProvisionInfra` targets |

It publishes two of its own, for the consumer to resolve at startup (the
consumer's role may read `/idp/provisioner/dev/*`):

| Parameter | Value |
|---|---|
| `/idp/provisioner/dev/scaffold_state_machine_arn` | What `StartExecution` takes |
| `/idp/provisioner/dev/requests_table_name` | The request-state table |

There is no `terraform_remote_state` read, so this workspace needs no access to
any other workspace's state.

Because it creates a ServiceAccount in a cluster it does not own, its pipeline
role `github-actions-tf-provisioner` needs an EKS access entry — granted through
`cluster_admin_principal_arns` in `infra/live/api/dev/dev.tfvars`. Without one
the kubernetes provider fails with a bare `Unauthorized`.

## Usage

```sh
cd infra/live/provisioner/dev
terraform init
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

## Teardown

Deleting a STANDARD state machine is asynchronous, and Step Functions removes it
only once every running execution has ended. A `.waitForTaskToken` execution
waiting on a callback nobody answers therefore holds the destroy open until that
task's timeout expires, which is 30 minutes by default.

Stop them first, or the destroy waits out the module's `delete_timeout` and
fails on a deletion that then completes on its own, leaving the role and the log
group behind:

```sh
sm=$(terraform output -raw scaffold_state_machine_arn)
aws stepfunctions list-executions --state-machine-arn "$sm" --status-filter RUNNING \
  --query 'executions[].executionArn' --output text |
  xargs -r -n1 aws stepfunctions stop-execution --cause "platform teardown" --execution-arn
```

A destroy that already failed this way is safe to re-run: the machine is gone
from AWS, so the provider treats the delete as done and removes the rest.

## What is deliberately not here

- **The SQS queue the consumer reads.** It is the seam between the API and this
  service; the API component owns it, and both services are granted one side.
- **The scaffolder's task queues.** The scaffolder owns them along with the IAM
  split that makes them separate queues at all; this stack is only a sender.
- **The infra worker's queue.** The `infra-worker-aws` component owns it. With
  `infra_worker_task_queue_name` null, a request naming cloud resources fails at
  `ProvisionInfra` rather than reporting success for resources nothing created.
- **The Deployment.** Kubernetes workloads are applied with `kubectl` from
  `k8s/provisioner/`, never by Terraform.
