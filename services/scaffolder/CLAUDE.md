# Scaffolder Service

> **Status: partially built.** The solution builds and its tests pass. What is
> real today: the six projects, the dependency rule (enforced by a test), the
> `ReserveName` handler, and the DynamoDB name-reservation adapter. Still design
> only: `template.yaml` and every other handler, the table itself, the templates,
> CI/CD, and observability. Sections below describing those are intent, not
> working code.
>
> **Build progress is tracked in [`PROGRESS.md`](./PROGRESS.md)**. Read this file
> for *what the service is*; read that one for *what is done and what is next*.

.NET service that owns the **repository domain** of the platform: given an
application request, it creates a GitHub repository, renders a golden-path
template into it, wires up CI/CD, and records what it built. It runs as a set of
AWS Lambda functions invoked as task states in a Step Functions state machine.

Target framework: **.NET 10 (LTS)**, Lambda runtime identifier **`dotnet10`** on
Amazon Linux 2023. It is a managed runtime — zip package type, no container image
— GA since 8 January 2026 and deployable through SAM. Runtime deprecation is
14 November 2028.

Do not target .NET 8: `dotnet8` deprecates **10 November 2026**, and `dotnet9` is
container-only with the same date.

Dev box toolchain: .NET SDK 10.0.110, SAM CLI 1.165.0, Docker 29.7.2. On Ubuntu
24.04 the SDK comes straight from the distro archive
(`sudo apt install dotnet-sdk-10.0`); no Microsoft package repo is needed.

## Why this service is serverless

The rest of the platform runs on EKS Fargate and is deployed with Terraform. This
service deliberately does not, for two reasons:

1. Its work is spiky and event-driven — a scaffold request arrives, runs for
   seconds, and stops. Lambda fits that shape better than a long-lived pod, and
   scaffolding traffic does not justify capacity sitting idle between requests.
2. It is the only service whose critical path is a third-party API. Keeping it
   off the cluster means a GitHub outage or a rate-limit backoff cannot consume
   pod capacity that the request-serving path depends on.

**IaC boundary:** SAM (`template.yaml`) owns everything belonging to this service
— functions, aliases, the DynamoDB table, the S3 bucket, per-function IAM roles.
Terraform keeps owning shared, long-lived infrastructure (VPC, ECR, Cognito, the
EventBridge bus, the Step Functions state machine itself). This is a deliberate
exception to the repo-wide Terraform convention; do not migrate shared
infrastructure into SAM.

## Place in the platform

```
Developer
   │ POST /v1/applications
   ▼
API (Go) ──SQS──▶ Provisioner (Go)          ← orchestrator: owns saga state,
                       │ StartExecution        starts the execution
                       ▼
             ┌──── Step Functions ─────────────────────────┐
             │ ReserveName          → Scaffolder (.NET)    │
             │ CreateRepository     → Scaffolder (.NET)    │
             │ ProvisionInfra       → Infra Worker (Go)    │  .waitForTaskToken
             │ PushScaffold         → Scaffolder (.NET)    │
             │ InjectInfraOutputs   → Scaffolder (.NET)    │
             │ ConfigureCiCd        → Scaffolder (.NET)    │
             │ RegisterRepository   → Scaffolder (.NET)    │
             │ (Catch) Compensate   → Scaffolder (.NET)    │
             └─────────────────────────────────────────────┘
```

`CreateRepository` and `ProvisionInfra` can run in parallel — creating a repo does
not depend on infrastructure existing. Only `InjectInfraOutputs` needs both, so it
is the join. Keep it that way: serializing them makes a developer wait for a
multi-minute Terraform run before they can see their repository, and "time to
first commit" is the metric this platform is judged on.

**Ownership boundary.** The provisioner owns saga/request state. This service owns
templates, name reservations, and the repository inventory, in its own DynamoDB
table. Neither service reads the other's table — they communicate only through the
state machine's input/output.

## Layout

```
src/
  Scaffolder.Domain/          - entities, value objects, port interfaces; no refs at all
  Scaffolder.Application/     - one use case per state machine task
  Scaffolder.Infrastructure/  - adapters: GitHub, DynamoDB, S3, Secrets Manager
  Scaffolder.Functions/       - Lambda entry points; thin, one handler per task
tests/
  Scaffolder.UnitTests/       - xUnit, domain + application + handler wiring
  Scaffolder.IntegrationTests/- adapters against LocalStack / a test GitHub org
templates/                    - golden paths (dotnet-api, then consumer and console)
events/                       - `sam local invoke` payloads
Directory.Build.props         - TFM, nullable, langversion, warnings-as-errors
Directory.Packages.props      - every package version, pinned centrally
Scaffolder.slnx               - the .NET 10 SDK's XML solution format, not .sln
Makefile
template.yaml                 - SAM: functions, table, bucket, aliases, IAM (not written yet)
samconfig.toml                - (not written yet)
```

Dependency rule mirrors the Go API's hexagonal layout: `Domain` depends on
nothing, `Application` depends on domain ports, `Infrastructure` implements them,
`Functions` is composition + serialization only. Business logic must not live in a
Lambda handler — handlers deserialize, call a use case, and serialize the result,
so the same logic is testable without invoking Lambda.

This is not an honour system: `tests/Scaffolder.UnitTests/Architecture/DependencyRuleTests.cs`
parses the project files and fails the build if a layer grows a reference it
should not have, or if a package version is declared outside
`Directory.Packages.props`.

**Cold start is a design constraint, not a detail.** `FunctionHost` builds the DI
container in a static initializer, so it runs during INIT, once per execution
context; every registration is a singleton so the SDK clients, credentials and
TLS connections survive across warm invocations. Configuration is read there too,
so a missing environment variable fails as an init error rather than as a
NullReference on the first request. Handlers keep no request state in statics —
the only static state is `ExecutionContextTelemetry`, which exists precisely to
show which invocations shared a context.

## DynamoDB (single table)

One table, `scaffolder`, owned entirely by this service.

| Item | PK | SK | Purpose |
|---|---|---|---|
| Template version | `TEMPLATE#<name>` | `VERSION#<semver>` | S3 bundle key, checksum, parameter schema |
| Name reservation | `NAME#<app-name>` | `RESERVATION` | request id, status, TTL |
| Repository record | `REPO#<owner>/<name>` | `META` | source template + version, request id, created_at |

- **GSI1** (`template#version` → repos) answers *"which repositories are behind the
  current template version?"* — the day-2 drift question that separates a real
  scaffolder from a demo. Design for it now even if the reporting comes later.
- **Name reservation is a conditional write**
  (`attribute_not_exists(PK)`), which makes uniqueness a single atomic operation
  instead of a read-then-write race.
- **Every state transition is a conditional write** on the expected current
  status. Step Functions retries and at-least-once delivery mean handlers *will*
  be invoked more than once for the same input; conditional writes make the
  duplicate a no-op instead of a second repository.
- **TTL** on reservations so abandoned requests release their name automatically.

## Templates

Source of truth is `templates/` in this repo. CI packages each directory into a
versioned bundle and uploads it to the S3 template bucket (versioning enabled);
DynamoDB records the version and checksum. Lambdas never read `templates/` from
the repo — always from S3 by version, so a scaffold is reproducible.

A template is not just `dotnet new` output. Each one carries the things that make
a service production-shaped on day zero:

- service code in the platform's layout
- OTel SDK pre-wired to the Collector, with `service.name` / `service.version` /
  `deployment.environment` set the same way the Go services set them
- health and readiness endpoints, graceful shutdown, structured JSON logging
- `Dockerfile` and `k8s/deployment.yaml` matching the existing manifests
- CI/CD workflows following the repo's `ci-` / `cd-` / `ops-` naming convention
- `CLAUDE.md`, README, and an `docs/adr/` directory
- Terraform stub for the service's own resources (IRSA role, ECR repo)
- catalog registration metadata (owner, team, on-call, tier)

## Configuration

Env vars, set by SAM per function. No config file.

- `SCAFFOLDER_TABLE_NAME` (required), `TEMPLATE_BUCKET`
- `SCAFFOLDER_RESERVATION_TTL_MINUTES` — how long an unfinished scaffold holds a
  name before TTL releases it. Defaults to 360 (6 hours): long enough to outlive a
  slow Terraform run, short enough that an abandoned request frees the name the
  same day
- `GITHUB_APP_ID`, `GITHUB_ORG` — in dev these are `4608314` and the sandbox org
  `idp-scaffolder-sandbox`. The sandbox exists to be filled with disposable
  repositories; never point dev at a real org

There is deliberately **no `GITHUB_INSTALLATION_ID`**. Resolve the installation at
runtime with `GET /orgs/{org}/installation` using the app JWT, then exchange it for
an installation token. One less config value, and it survives the app being
uninstalled and reinstalled — which changes the installation ID but not the App ID.
- `GITHUB_APP_KEY_SECRET_ARN` — Secrets Manager ARN for the GitHub App private
  key. Never a PAT, never an env var holding the key itself.
- `ENVIRONMENT`, `SERVICE_VERSION`, `SERVICE_NAME`

Secrets are fetched at cold start and cached for the container's lifetime — not
per invocation, which would add a Secrets Manager call to every request.

## Security

- **GitHub App, not a PAT.** Short-lived installation tokens, scoped to the org,
  revocable, and auditable per-repository.
- **Per-function IAM roles.** One role per Lambda in `template.yaml`, each granted
  only what that function touches. Do not share a single "scaffolder role" — a
  function that only reserves a name has no business holding permission to create
  repositories or read the GitHub App key.
- **KMS** for the template bucket and the secret. Customer-managed key so key
  policy and rotation are explicit.

## Deployment

SAM, from GitHub Actions, following the repo's `cd-` workflow convention
(`cd-scaffolder.yml`). Use the existing `aws-oidc-login` composite action — no
long-lived AWS keys.

- `AutoPublishAlias: live` — every deploy publishes a new version and moves the
  alias.
- `DeploymentPreference: Canary10Percent5Minutes` with CloudWatch alarms, so a
  bad deploy rolls back automatically via CodeDeploy.

## Observability

The platform's rule is vendor-agnostic OpenTelemetry, and this service keeps it —
but Lambda constrains how.

- Use the **ADOT (AWS Distro for OpenTelemetry) Lambda layer**, not the X-Ray SDK.
  ADOT speaks W3C trace context, which is what the Go services propagate, so a
  scaffold request stays **one distributed trace** from API → SQS → provisioner →
  Step Functions → these functions. The X-Ray SDK's native header format would
  break that continuity.
- The OTel Collector runs inside the EKS cluster, so these functions cannot reach
  it unless they are VPC-attached. Simplest v1: ADOT exports to X-Ray and
  CloudWatch directly. Only attach to the VPC if something else forces it — it
  costs cold-start time and ENI management.
- Metrics via **CloudWatch EMF** (structured logs → metrics) rather than a
  separate metrics pipeline; it is the idiomatic Lambda approach and avoids
  needing a Collector route.
- Enable X-Ray active tracing on the state machine — the execution graph with
  timings is the fastest way to see which step is slow.
- Alarms on function errors, throttles, and duration feed the canary deployment
  gate above.

## Testing

- `dotnet test` — xUnit. Domain and application layers test with no AWS.
- Adapters test against LocalStack (DynamoDB, S3, Secrets Manager) and a
  throwaway GitHub org.
- `sam local invoke` with event fixtures for handler-level checks.
- The compensation path (`Compensate`) needs tests as much as the happy path. It
  runs rarely, which is exactly why it rots — assert that a failed scaffold leaves
  no repository and no reservation behind.

## Commands

`make` from this directory lists the targets. The common ones:

```bash
make build                        # dotnet build
make test                         # unit tests: no AWS, no Docker, no network
make test-integration             # adapters against LocalStack + the sandbox org (opt-in)
make format-check                 # dotnet format --verify-no-changes
make invoke F=ReserveName E=events/reserve-name.json   # sam build + sam local invoke
sam deploy --config-env dev       # deploy
```

Integration tests are opt-in via `SCAFFOLDER_INTEGRATION=1` because they need
Docker and credentials; without it xUnit skips rather than fails them.
