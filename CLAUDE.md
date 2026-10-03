# Internal Developer Platform

Monorepo for an internal developer platform that provisions cloud resources.

## Architecture

Event-driven, multi-service platform. The control plane runs on AWS (EKS, SQS, Cognito,
Step Functions); the platform is **multi-cloud** in what it provisions: every requested
resource carries a `cloud_provider` (`AWS`, `Azure`, `GCP`), and each provider has its own
infra worker. See [ADR-0008](docs/adr/0008-one-infra-worker-per-cloud-provider.md).

1. **API** (`/services/api`) — Go 1.26 REST API. Receives provision requests — one request carries both the application to scaffold and the cloud resources it needs — and publishes them to SQS.
2. **Provisioner** (`/services/provisioner`) — Go 1.25 service and the control plane. Consumes SQS messages and splits each request into the work each downstream worker owns: the repository half for the scaffolder, the resources half for the infra worker. Its Terraform component owns the **scaffold Step Functions state machine** and the request-state table; the service does not start executions yet.
3. **Scaffolder** (`/services/scaffolder`) — .NET 10 container on EKS. Owns the repository domain: creates GitHub repos from golden-path templates and wires their CI/CD. Consumes Step Functions `.waitForTaskToken` messages off its own SQS queues, as two Deployments of one image split by what they are trusted with — only the `github` one can read the GitHub App private key. **Under construction** — the solution, the `ReserveName` and `CreateRepository` tasks, the GitHub App adapter, the image and its Terraform component exist, and the state machine now targets both queues; nothing is deployed yet, and no code upstream starts an execution.
4. **Infra workers** (`/services/infra-workers/<provider>`) — one Go service per cloud
   provider, each with its own queue and its own credentials for that cloud only. Each executes
   infrastructure-as-code as a `.waitForTaskToken` task in the same state machine, and receives
   only resources whose `cloud_provider` it owns; routing by provider is the control plane's job.
   **AWS** (`/services/infra-workers/aws`) is the first and only one: it logs each `ProvisionInfra`
   task and acknowledges it, with no Terraform, no reply to Step Functions and nothing deployed.
   Azure and GCP workers are planned.

Message flow: API → SQS → Provisioner → Step Functions → task workers

The state machine is defined in `infra/live/provisioner/dev/state_machine.tf` and
built by `infra/modules/aws/step_functions`. It lives with the provisioner because
the provisioner is the control plane and the workflow spans both workers; it
reaches the scaffolder's task queues by name through SSM. See
[ADR-0006](docs/adr/0006-step-functions-as-provisioning-orchestrator.md).

The request contract is defined in `services/api/internal/domain/model/resource.go` and
**duplicated** in `services/provisioner/internal/provision/request.go`. Separate modules and
separate deployables, so a shared struct would make a field rename in one a compile break in the
other — the coupling a queue exists to remove. Change them together.

Until a worker reports results, the machine's `ProvisionInfra` state is a `Fail` state, so a
request naming cloud resources fails rather than reporting success for resources nothing
created; setting `infra_worker_task_queue_name` turns it into the callback task.
The provisioner service itself is still a bare consume loop: it logs both halves of a request
instead of calling `StartExecution`.

## Conventions

- Each service has its own `CLAUDE.md` with service-specific details — read it before working on that service.
- When a change alters a service's architecture, commands, or conventions, update that service's CLAUDE.md in the same commit.
- Go services use standard `cmd/` and `internal/` layout.
- Infrastructure follows Terraform `modules/` + `live/` pattern, with no exceptions: every AWS
  resource in the platform is Terraform-owned, and every workload is a container deployed with
  `kubectl`. The scaffolder was briefly a SAM/Lambda exception; see
  [ADR-0004](docs/adr/0004-scaffolder-runs-as-a-container-on-eks.md) for why it is not any more.
- Services own their own data. No service reads another service's table or database.

## Terraform documentation

Comments in `.tf` files are written for someone reading this repository on GitHub
for the first time, with no context on the platform. They explain **why** a thing
exists and what breaks without it. Terraform already states what a resource is.

**Every `.tf` file that declares resources opens with a 2–5 line header** saying what
it provisions and how that fits the platform — which service depends on it, what
would not work without it. Modules say what role they play across the platform;
`live/` stacks say what the stack owns and which contracts it publishes or consumes.
`backend.tf`, `versions.tf`, `providers.tf`, `outputs.tf` and `variables.tf` need no
header: `description` is the documentation mechanism for variables and outputs, and
every one of them must carry a meaningful one.

**Inline comments are for non-obvious things only** — an AWS constraint, a
plan-time/apply-time ordering trap, a deliberate trade-off, a value that must stay in
sync with something outside the file. Two or three sentences at most. A parameter
whose name already explains it gets no comment.

**Do not write:**

- Banner blocks (`# ====`, `# ####`, `# ----`) or section headers that restate the
  code beneath them: `# SQS QUEUE`, `# Outputs for X`, `# Variables for Y`,
  `# RULE 3: Rate Limiting`.
- Changelog or history: "was removed", "no longer", "used to", "now", "the ECS-era
  contract", "kept during the transition". Git holds that. Comments describe the code
  as it stands.
- Emphasis by capitalisation (`NOT`, `NEVER`, `ONLY`), rhetorical framing, or asides
  addressed to the reader ("worth reading", "the whole point", "note that").
- Em dashes. Use a colon, a semicolon, or a second sentence.
- First person, singular or plural.
- Essays. If a decision needs several paragraphs, it is an ADR under `docs/adr/`;
  reference it from the file instead.

**Keep comments true.** A comment that contradicts the code beneath it is worse than
no comment. When a resource changes, its comment changes in the same commit.

Run `terraform fmt -recursive` before committing; it parses the HCL and catches
anything a comment edit broke.
