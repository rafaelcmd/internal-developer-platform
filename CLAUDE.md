# Internal Developer Platform

Monorepo for an internal developer platform that provisions cloud resources.

## Architecture

Event-driven, multi-service platform. The control plane runs on AWS (EKS, SQS, Cognito,
Step Functions); the platform is **multi-cloud** in what it provisions: every requested
resource carries a `cloud_provider` (`AWS`, `Azure`, `GCP`), and each provider has its own
infra worker. See [ADR-0008](docs/adr/0008-one-infra-worker-per-cloud-provider.md).

1. **API** (`/services/api`) — Go 1.26 REST API. Receives provision requests — one request carries both the application to scaffold and the cloud resources it needs — and publishes them to SQS.
2. **Provisioner** (`/services/provisioner`) — Go 1.25 service and the control plane. Consumes SQS messages and splits each request into the work each downstream worker owns: the repository half for the scaffolder, the resources half for the infra worker. Its Terraform component owns the **scaffold Step Functions state machine** and the request-state table, and the service starts one execution per request, named after its `request_id`.
3. **Scaffolder** (`/services/scaffolder`) — .NET 10 container on EKS. Owns the repository domain: creates GitHub repos from golden-path templates and wires their CI/CD. Consumes Step Functions `.waitForTaskToken` messages off its own SQS queues, as two Deployments of one image split by what they are trusted with — only the `github` one can read the GitHub App private key. **Under construction** — the solution, the `ReserveName` and `CreateRepository` tasks, the GitHub App adapter, the image and its Terraform component exist, and the state machine now targets both queues; nothing is deployed yet, and no code upstream starts an execution.
4. **Infra workers** (`/services/infra-workers/<provider>`) — one Go service per cloud
   provider, each with its own queue and its own credentials for that cloud only. Each executes
   infrastructure-as-code as a `.waitForTaskToken` task in the same state machine, and receives
   only resources whose `cloud_provider` it owns; routing by provider is the control plane's job.
   **AWS** (`/services/infra-workers/aws`) is the first and only one: it logs each `ProvisionInfra`
   task, reports it to Step Functions as succeeded with `Provisioned: false`, and runs no
   Terraform yet. Its queue and role are the `infra-worker-aws` Terraform component
   (`infra/live/infra_worker_aws/dev`). Azure and GCP workers are planned.

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

`ProvisionInfra` targets the AWS worker's queue through `infra_worker_task_queue_name`; with it
null the state is a `Fail` state, so a request naming cloud resources fails rather than reporting
success for resources nothing created. In dev, `scaffold_enabled = false` turns the scaffolder's
states into Pass states, so an execution runs API → provisioner → state machine → AWS infra worker
without the scaffolder.

## Architecture diagrams

The C4 diagrams in `docs/architecture/c4/` are the picture of the architecture above, and
`README.md` embeds their PNGs. **Every architecture change updates them in the same commit**:

- Adding, removing or renaming a service, worker, queue, table, state machine state or
  external system; changing who calls whom, over what transport; moving a workload; or
  changing a component's status (planned, under construction, built).
- Edit the `.puml` source, never only the PNG. Which file changes depends on the level:
  `01-system-context` (people and external systems), `02-container` (deployables and data
  stores), `03-component-api` / `04-component-provisioner` (a service's internals),
  `05-dynamic-provision-request` (the request flow and state machine order),
  `06-deployment` (where things run). A new service with real internals gets its own
  `0N-component-<service>.puml` and a section in `README.md`.
- Re-render with `docs/architecture/c4/render.sh` (local `plantuml` or Docker) and commit
  the regenerated PNGs with the source. A PNG that disagrees with its `.puml` is a stale
  diagram.
- Show unbuilt parts with the `planned` tag (dashed) and partly built ones with
  `in_progress`, so the diagrams stay true about what exists.

## Conventions

- Each service has its own `CLAUDE.md` with service-specific details — read it before working on that service.
- When a change alters a service's architecture, commands, or conventions, update that service's CLAUDE.md in the same commit.
- Go services use standard `cmd/` and `internal/` layout.
- Infrastructure follows Terraform `modules/` + `live/` pattern, with no exceptions: every AWS
  resource in the platform is Terraform-owned, and every workload is a container deployed with
  `kubectl`. The scaffolder was briefly a SAM/Lambda exception; see
  [ADR-0004](docs/adr/0004-scaffolder-runs-as-a-container-on-eks.md) for why it is not any more.
- Services own their own data. No service reads another service's table or database.

## Terraform locals

Terraform treats every `.tf` file in a directory as one module, so a local can be
declared in any file and read from any other. These rules keep that from hiding
dependencies between files:

- **A local read by more than one file goes in that module's `locals.tf`.**
  Create the file if the module has none. Reading it from `outputs.tf` counts.
- **A local read by only one file stays in that file**, next to the
  resources that use it. When a second file starts reading it, move it to
  `locals.tf` in the same change.
- **Exception: a file that declares only locals**, built around one shared
  construct with a header explaining it, may stay a file of its own.
  `live/shared/iam-github-oidc/workload_iam.tf`, the IAM statements every
  component pipeline shares, is the one case today. Use this rarely; plain values
  such as tags, ARNs, paths and name prefixes always go in `locals.tf`.
- `locals.tf` declares no resources, so it needs no file header. A comment on an
  individual local follows the inline-comment rules below.

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
