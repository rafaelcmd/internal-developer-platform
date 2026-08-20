# Scaffolder Service

> **Status: partially built.** The solution builds, its tests pass, and the
> worker runs locally against LocalStack. What is real today: the six projects,
> the dependency rule (enforced by a test), the `ReserveName` task, the DynamoDB
> name-reservation adapter, the container image, the Kubernetes Deployment, and
> the `scaffolder` Terraform component that owns its table, task queue and IRSA
> role. Nothing is deployed yet. Still design only: every other task, the state
> machine, the templates, and the GitHub adapter. Sections below describing
> those are intent, not working code.

.NET service that owns the **repository domain** of the platform: given an
application request, it creates a GitHub repository, renders a golden-path
template into it, wires up CI/CD, and records what it built. It runs as a
long-lived container on EKS Fargate, consuming task tokens from the scaffold
state machine.

Target framework: **.NET 10 (LTS)**. Dev box toolchain: .NET SDK 10.0.111,
Docker 29.7.2. On Ubuntu 24.04 the SDK comes straight from the distro archive
(`sudo apt install dotnet-sdk-10.0`); no Microsoft package repo is needed.

## Why this service is a container

It was originally Lambda functions deployed with AWS SAM.
[ADR-0004](../../docs/adr/0004-scaffolder-runs-as-a-container-on-eks.md) records
why that changed; the short version:

1. The OTel Collector runs **in-cluster**, and Lambda cannot reach it without
   being VPC-attached. Off-cluster, a scaffold request's trace fragmented across
   two backends — Datadog for API → SQS → provisioner, X-Ray for the seven steps
   that do the actual work.
2. On **Fargate** every pod is its own microVM, so the "keep it off the cluster
   so a GitHub outage cannot eat pod capacity" argument does not apply.
3. The Infra Worker is already a container consuming `.waitForTaskToken`
   messages, so that plumbing exists regardless.

**IaC boundary: there isn't one any more.** Terraform owns every AWS resource
this service uses, in `infra/live/scaffolder/dev`. Kubernetes owns the workload,
in `k8s/scaffolder/`. Do not reintroduce SAM or CloudFormation —
`DependencyRuleTests.Nothing_references_the_lambda_runtime` fails the build if
an `Amazon.Lambda.*` package comes back.

## Place in the platform

```
Developer
   │ POST /v1/applications
   ▼
API (Go) ──SQS──▶ Provisioner (Go)          ← orchestrator: owns saga state,
                       │ StartExecution        starts the execution
                       ▼
             ┌──── Step Functions ─────────────────────────┐
             │ ReserveName          → Scaffolder (.NET)    │  .waitForTaskToken
             │ CreateRepository     → Scaffolder (.NET)    │  .waitForTaskToken
             │ ProvisionInfra       → Infra Worker (Go)    │  .waitForTaskToken
             │ PushScaffold         → Scaffolder (.NET)    │
             │ InjectInfraOutputs   → Scaffolder (.NET)    │
             │ ConfigureCiCd        → Scaffolder (.NET)    │
             │ RegisterRepository   → Scaffolder (.NET)    │
             │ (Catch) Compensate   → Scaffolder (.NET)    │
             └─────────────────────────────────────────────┘
```

Every scaffolder state is a `.waitForTaskToken` task: Step Functions puts a
message on **one** queue carrying the task name, the payload and the callback
token, and the worker dispatches on the name. One queue and one Deployment serve
every task — adding a task is a use case plus a line in `TaskDispatcher`, never
a new deployment.

`CreateRepository` and `ProvisionInfra` can run in parallel — creating a repo
does not depend on infrastructure existing. Only `InjectInfraOutputs` needs both,
so it is the join. Keep it that way: serializing them makes a developer wait for
a multi-minute Terraform run before they can see their repository, and "time to
first commit" is the metric this platform is judged on.

**Ownership boundary.** The provisioner owns saga/request state. This service
owns templates, name reservations, and the repository inventory, in its own
DynamoDB table. Neither service reads the other's table — they communicate only
through the state machine's input/output.

## Layout

```
src/
  Scaffolder.Domain/          - entities, value objects, port interfaces; no refs at all
  Scaffolder.Application/     - one use case per state machine task
  Scaffolder.Infrastructure/  - adapters: GitHub, DynamoDB, S3, Secrets Manager
  Scaffolder.Worker/          - entry point: host, task queue consumer, dispatcher
tests/
  Scaffolder.UnitTests/       - xUnit, domain + application + dispatcher wiring
  Scaffolder.IntegrationTests/- adapters against LocalStack / a test GitHub org
templates/                    - golden paths (dotnet-api, then consumer and console)
events/                       - task-envelope fixtures for `make seed`
local/                        - LocalStack init script; creates the table and queue
Directory.Build.props         - TFM, nullable, langversion, warnings-as-errors
Directory.Packages.props      - every package version, pinned centrally
Scaffolder.slnx               - the .NET 10 SDK's XML solution format, not .sln
Dockerfile.dev                - multi-stage build; runtime image, non-root
docker-compose.dev.yaml       - the worker plus LocalStack; included by the root compose
Makefile
```

Infrastructure lives outside this directory, with everything else of its kind:
`infra/live/scaffolder/dev` (table, task queue, IRSA) and `k8s/scaffolder`
(Deployment).

Dependency rule mirrors the Go API's hexagonal layout: `Domain` depends on
nothing, `Application` depends on domain ports, `Infrastructure` implements them,
`Worker` is composition + serialization only. Business logic must not live in the
worker — it deserializes, calls a use case, serializes the result, so the same
logic is testable without a queue. Swapping Lambda for a container touched only
`Scaffolder.Worker`, which is the layering paying for itself.

This is not an honour system:
`tests/Scaffolder.UnitTests/Architecture/DependencyRuleTests.cs` parses the
project files and fails the build if a layer grows a reference it should not
have, if a package version is declared outside `Directory.Packages.props`, or if
the queue and hosting packages escape `Scaffolder.Worker`.

## How the worker runs a task

`TaskQueueWorker` is a `BackgroundService`. At startup it resolves the queue
**name** to a URL — so no account id lands in the committed manifest — then long
polls it for 20s at a time.

The **deletion rule** is the thing to understand before changing it: a message is
deleted only once its outcome has reached Step Functions, by `SendTaskSuccess` or
`SendTaskFailure`. Everything else — an unparseable body, a missing token, a
transient AWS fault — is left on the queue, so SQS redelivers it and the DLQ
catches it after `maxReceiveCount`. Deleting on failure would strand the
execution until its task timeout with nothing to look at.

Error names are ours now. On Lambda the `Catch` clause had to match whatever the
runtime reported (the short exception type name). The worker chooses, so it sends
the domain's own `ScaffolderException.Code` — a stable contract that survives
renaming a class.

Configuration is read and validated in `Program.cs` before the host starts, so a
missing table name is a CrashLoopBackOff at startup rather than a null reference
on the first task.

## DynamoDB (single table)

One table, owned entirely by this service, created by
`infra/live/scaffolder/dev`.

| Item | PK | SK | Purpose |
|---|---|---|---|
| Template version | `TEMPLATE#<name>` | `VERSION#<semver>` | S3 bundle key, checksum, parameter schema |
| Name reservation | `NAME#<app-name>` | `RESERVATION` | request id, status, TTL |
| Repository record | `REPO#<owner>/<name>` | `META` | source template + version, request id, created_at |

- **GSI1** (`template#version` → repos) answers *"which repositories are behind
  the current template version?"* — the day-2 drift question that separates a
  real scaffolder from a demo. Not created yet; design for it now.
- **Name reservation is a conditional write**
  (`attribute_not_exists(PK) OR RequestId = :requestId`), which makes uniqueness
  a single atomic operation instead of a read-then-write race.
- **Every state transition is a conditional write** on the expected current
  status. Step Functions retries and at-least-once SQS delivery mean tasks *will*
  run more than once for the same input; conditional writes make the duplicate a
  no-op instead of a second repository. This is also what gates scaling the
  Deployment past one replica.
- **TTL** on `ExpiresAt` (epoch seconds) so abandoned requests release their name
  automatically.

## Templates

Source of truth is `templates/` in this repo. CI packages each directory into a
versioned bundle and uploads it to the S3 template bucket (versioning enabled);
DynamoDB records the version and checksum. The worker never reads `templates/`
from the repo — always from S3 by version, so a scaffold is reproducible.

A template is not just `dotnet new` output. Each one carries the things that make
a service production-shaped on day zero:

- service code in the platform's layout
- OTel SDK pre-wired to the Collector, with `service.name` / `service.version` /
  `deployment.environment` set the same way the Go services set them
- health and readiness endpoints, graceful shutdown, structured JSON logging
- `Dockerfile` and `k8s/deployment.yaml` matching the existing manifests
- CI/CD workflows following the repo's `ci-` / `cd-` / `ops-` naming convention
- `CLAUDE.md`, README, and a `docs/adr/` directory
- Terraform stub for the service's own resources (IRSA role, ECR repo)
- catalog registration metadata (owner, team, on-call, tier)

## Configuration

Env vars, set by `k8s/scaffolder/deployment.yaml`. No config file.

- `SCAFFOLDER_TABLE_NAME` (required)
- `SCAFFOLDER_TASK_QUEUE_NAME` (required) — the **name**, not the URL. The worker
  calls `GetQueueUrl` at startup, which keeps the account id out of git and lets
  the same manifest run in any account
- `SCAFFOLDER_RESERVATION_TTL_MINUTES` — how long an unfinished scaffold holds a
  name before TTL releases it. Defaults to 360 (6 hours): long enough to outlive
  a slow Terraform run, short enough that an abandoned request frees the name the
  same day
- `TEMPLATE_BUCKET` — not wired yet
- `GITHUB_APP_ID`, `GITHUB_ORG` — in dev these are `4608314` and the sandbox org
  `idp-scaffolder-sandbox`. The sandbox exists to be filled with disposable
  repositories; never point dev at a real org
- `GITHUB_APP_KEY_SECRET_ARN` — Secrets Manager ARN for the GitHub App private
  key. Never a PAT, never an env var holding the key itself
- `ENVIRONMENT`, `SERVICE_VERSION`, `SERVICE_NAME`
- `OTEL_EXPORTER_OTLP_ENDPOINT` — telemetry is a **no-op when unset**, matching
  the Go services, which is what keeps `dotnet run` on a laptop quiet

There is deliberately **no `GITHUB_INSTALLATION_ID`**. Resolve the installation at
runtime with `GET /orgs/{org}/installation` using the app JWT, then exchange it
for an installation token. One less config value, and it survives the app being
uninstalled and reinstalled — which changes the installation ID but not the App
ID.

Secrets are fetched once at startup and cached for the pod's lifetime — not per
task, which would add a Secrets Manager call to every request.

## Security

- **GitHub App, not a PAT.** Short-lived installation tokens, scoped to the org,
  revocable, and auditable per-repository.
- **One IRSA role today, two soon.** On Lambda each function had its own role, so
  the handler that reserved a name could not read the GitHub App key. A single
  pod cannot express that. The role in `infra/live/scaffolder/dev/irsa.tf` is
  therefore kept to DynamoDB, the task queue and the Step Functions callbacks —
  and ADR-0004 commits to splitting into two Deployments with two roles (state
  operations, GitHub operations) when the GitHub adapter lands. Do not widen the
  single role to cover the secret; add the second Deployment instead.
- **KMS** for the template bucket and the secret. Customer-managed key so key
  policy and rotation are explicit.

## Deployment

`cd-scaffolder.yml`, following `cd-provisioner.yml` exactly: build the image,
push it to the shared ECR repository as `scaffolder-<sha>`, pin that tag into the
manifest, `kubectl apply`, wait for the rollout. Uses the existing
`aws-oidc-login` composite — no long-lived AWS keys.

Terraform first: the `scaffolder` component owns the ServiceAccount the pod binds
to, so a deploy against a fresh cluster fails without it. `ops-platform-up.yml`
encodes that ordering.

There is no automatic rollback on alarm. That is what Lambda's
`DeploymentPreference: Canary10Percent5Minutes` gave for free and a Kubernetes
rolling update does not — a known cost of ADR-0004, not an oversight.

## Observability

Identical to the Go services, which is the point:

- OTLP over gRPC to `otel-collector.observability.svc.cluster.local:4317`, which
  forwards to Datadog. `service.name` / `service.version` /
  `deployment.environment` are set from the same env vars the Go services use, so
  a scaffold shows up as part of the request that triggered it rather than as an
  orphan trace.
- The state machine propagates W3C trace context, so the worker's spans join the
  trace the API opened.
- `AddAWSInstrumentation()` puts SDK calls on the trace, so a slow DynamoDB write
  reads as its own span rather than unexplained time inside a task.
- Runtime metrics via `AddRuntimeInstrumentation()`, over the same OTLP pipe. No
  separate metrics path.
- Enable X-Ray active tracing on the state machine when it exists — the execution
  graph with timings is the fastest way to see which step is slow.

## Testing

- `dotnet test` — xUnit. Domain and application layers test with no AWS.
- Adapters test against LocalStack (DynamoDB, S3, Secrets Manager) and a
  throwaway GitHub org.
- `make up && make seed` for a hand check against LocalStack. Note what that does
  **not** cover: the fixture's task token is fake, so everything up to the
  callback runs for real and `SendTaskSuccess` is then rejected — see
  `events/README.md`.
- The compensation path (`Compensate`) needs tests as much as the happy path. It
  runs rarely, which is exactly why it rots — assert that a failed scaffold
  leaves no repository and no reservation behind.

## Commands

`make` from this directory lists the targets. The common ones:

```bash
make build                        # dotnet build
make test                         # unit tests: no AWS, no Docker, no network
make test-integration             # adapters against LocalStack + the sandbox org (opt-in)
make format-check                 # dotnet format --verify-no-changes
make up                           # worker + LocalStack via docker compose
make seed E=events/reserve-name.json   # put one task on the local queue
make logs                         # follow the worker
```

Integration tests are opt-in via `SCAFFOLDER_INTEGRATION=1` because they need
Docker and credentials; without it xUnit skips rather than fails them.

Two things that are easy to lose time to:

- **`Amazon.StepFunctions` also defines a `LogLevel`.** It collides with
  `Microsoft.Extensions.Logging.LogLevel` in any file that uses both;
  `Program.cs` carries a `using` alias for it.
- **The AWS SDK for .NET v4 leaves response collections null, not empty.**
  `ReceiveMessageResponse.Messages` is `null` when a long poll times out, which
  is the common case. `TaskQueueWorker` coalesces it; anything new reading an SDK
  collection must do the same.
