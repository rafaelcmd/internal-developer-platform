# Scaffolder Service — Build & DVA-C02 Study Tracker

> Living document. Tick boxes as you go; this is the source of truth for what is
> built and what is left. Architecture lives in [`CLAUDE.md`](./CLAUDE.md).

## Context

The platform provisions cloud resources but has no **Developer Control Plane** — nothing
turns a request into a working repository. Golden-path scaffolding (Backstage's "Software
Templates", Port's scaffolder) is a core IDP function and the one capability this repo lacks
entirely.

The Scaffolder fills it: given an application request, it creates a GitHub repository,
renders a golden-path template into it, wires CI/CD, and records what it built.

It is written in **.NET on Lambda, deployed with SAM** — deliberately unlike the Go/EKS/Terraform
services — because the work is spiky and event-driven, and because this project is the study
vehicle for **AWS DVA-C02**.

**Organised by exam topic, not delivery order.** Each block is a self-contained study unit
that builds one working piece of the scaffolder and ends with hands-on checks — including
deliberate failures, because Troubleshooting is 18% of the exam and cannot be studied by
reading.

## Scope

**In:** the .NET service — SAM template, Lambda handlers, its own DynamoDB table, S3 bucket,
state machine, the `dotnet-api` template, CI/CD, observability.

**Out (deferred):** `ApplicationRequest` in the Go API, provisioner-as-orchestrator, the Go
infra-worker, and the **shared platform** state machine. The scaffolder runs standalone so it
can be finished and verified without touching the Go services.

The scaffolder gets **its own** state machine, in SAM (B6). The shared platform machine still
belongs to Terraform when it arrives — it will invoke this one as a nested execution.

`InjectInfraOutputs` has no real infra outputs yet; build it against a fixture payload.

## Decisions locked in

| Decision | Choice | Why |
|---|---|---|
| Compute | Lambda, SAM-deployed | spiky workload; DVA-C02 coverage |
| GitHub auth | **GitHub App** | short-lived org-scoped tokens; real rotation use case |
| Templating | **Scriban** over an S3 file tree | pure .NET, no SDK in the runtime, supports conditionals |
| State store | DynamoDB single table | no VPC/pooling/migrations; conditional writes give idempotency free |
| IaC boundary | SAM owns this service; Terraform keeps shared infra | ADR in B9 |

## Progress

| Block | Topic | Domain | Status |
|---|---|---|---|
| B0 | Prerequisites | — | [ ] |
| B1 | Lambda fundamentals | 1 + 3 | [ ] |
| B2 | SAM & CloudFormation | 3 | [ ] |
| B3 | DynamoDB | 1 | [ ] |
| B4 | S3 | 1 + 2 | [ ] |
| B5 | Secrets Manager, KMS, IAM, STS | 2 | [ ] |
| B6 | Step Functions | 1 | [ ] |
| B7 | API Gateway *(optional)* | 1 + 2 | [ ] |
| B8 | EventBridge & SNS *(optional)* | 1 | [ ] |
| B9 | Deployment, versions & aliases | 3 | [ ] |
| B10 | Observability & troubleshooting | 4 | [ ] |

Domain weights: 1 — Development 32% · 2 — Security 26% · 3 — Deployment 24% · 4 — Troubleshooting 18%

**Dependency order.** B0–B3 are load-bearing, in order. B7 and B8 are independent once B3
lands. B10 runs continuously from B1 onward — saving observability for the end is how it ends
up unbuilt.

```
B0 ──▶ B1 ──▶ B2 ──▶ B3 ──▶ B4 ──▶ B5 ──▶ B6 ──▶ B9
                      │              │        │
                      └──────────────┴──▶ B7  └──▶ B8
                                          B10 (continuous)
```

---

## B0 — Prerequisites

- [x] Commit this document so progress is versioned with the code
- [x] Install the SDK — **.NET SDK 10.0.110** at `/usr/lib/dotnet/sdk`, from Ubuntu 24.04's
      own `noble-updates` archive (no Microsoft package repo needed)
- [x] Install the AWS SAM CLI and Docker — **SAM CLI 1.165.0**, **Docker 29.7.2** with the
      daemon running. `sam init --help` lists `dotnet10`, so the CLI knows the runtime
- [x] **Runtime settled: .NET 10, identifier `dotnet10`.** Managed runtime on Amazon Linux
      2023, GA since 8 Jan 2026, available in all regions, deployable via SAM / CDK /
      CloudFormation. Deprecates 14 Nov 2028. **No container image needed.**

      **Do not fall back to .NET 8.** `dotnet8` deprecates **10 Nov 2026** — under three
      months away — and `dotnet9` is container-only with the same date. .NET 10 is the only
      .NET runtime with real runway
- [x] Update `CLAUDE.md` with the runtime answer
- [ ] Create a throwaway GitHub org for testing
- [ ] Create a GitHub App installed on it: `Administration: write`, `Contents: write`,
      `Actions: write`, `Secrets: write`. Record the App ID; keep the private key for B5

---

## B1 — Lambda fundamentals · `Domain 1 + 3`

**Exam topics:** handler signature and the .NET Lambda runtime; execution context reuse; cold
vs warm start; memory/CPU coupling; timeout limits; `/tmp`; layers; environment variables;
reserved vs provisioned concurrency; throttling (`TooManyRequestsException`, 429); retry
behaviour by invocation type (sync = none from Lambda, async = 2 retries then DLQ/destination,
event source mapping = its own rules); deployment package limits.

**Build**
- [ ] Solution skeleton: `Scaffolder.sln`, `Directory.Build.props` (target framework, nullable,
      langversion in ONE place)
- [ ] Projects: `Scaffolder.Domain`, `Scaffolder.Application`, `Scaffolder.Infrastructure`,
      `Scaffolder.Functions`, plus `Scaffolder.UnitTests` / `Scaffolder.IntegrationTests`
- [ ] `events/` directory for `sam local invoke` payloads; `Makefile`
- [ ] Enforce the dependency rule from the first commit — `Domain` depends on nothing,
      `Application` on domain ports, `Infrastructure` implements them, `Functions` is
      composition and serialization only. **No business logic in a handler**
- [ ] `ReserveName` handler with DI container and AWS SDK clients initialised **outside** the
      handler method, so they land in the reused execution context

**Hands-on checks**
- [ ] Log a static counter to prove execution-context reuse across warm invocations
- [ ] Compare duration at 128MB vs 1024MB — observe the CPU coupling
- [ ] Set reserved concurrency to 0, invoke, watch it throttle
- [ ] Force a timeout and read what CloudWatch actually records

---

## B2 — SAM & CloudFormation · `Domain 3`

**Exam topics:** the `AWS::Serverless-2016-10-31` transform and what it expands into;
`AWS::Serverless::Function` / `::Api` / `::StateMachine` / `::SimpleTable`; `Globals`; SAM
**policy templates** vs hand-written IAM; intrinsic functions (`!Ref`, `!GetAtt`, `!Sub`,
`!If`); parameters, mappings, conditions, outputs, exports; changesets; stack states and
automatic rollback; nested stacks; `sam build / local invoke / local start-api / deploy /
sync / logs / traces`; `samconfig.toml` config environments.

**Build**
- [ ] `template.yaml` with the transform, a `Globals:` block, and the B1 function
- [ ] `samconfig.toml` with a `dev` config environment
- [ ] `sam deploy` succeeds

**Hands-on checks**
- [ ] Run `sam build`, then read `.aws-sam/build/template.yaml` — see exactly what the
      transform generated from your ten lines. Do this once and SAM stops being magic
- [ ] Deploy a deliberately broken template; watch CloudFormation roll the stack back
- [ ] Compare a SAM policy template against the raw IAM policy it produced

---

## B3 — DynamoDB · `Domain 1`

The single most heavily tested service on the exam. Budget the most time here.

**Exam topics:** partition and sort keys; single-table design; **LSI vs GSI** (LSI only at
table creation; GSI can be added later with a backfill; GSI reads are always eventually
consistent); index projections; on-demand vs provisioned; RCU/WCU maths; eventually vs
strongly consistent reads; **conditional writes**; optimistic locking with version attributes;
atomic counters; `TransactWriteItems`; `BatchGetItem` / `BatchWriteItem` and `UnprocessedKeys`;
Query vs Scan; pagination via `LastEvaluatedKey`; the 400KB item and 1MB page limits; TTL;
Streams; DAX; `ProvisionedThroughputExceededException` and exponential backoff.

**Build**
- [ ] Single table with all three key shapes at once:

  | Item | PK | SK |
  |---|---|---|
  | Template version | `TEMPLATE#<name>` | `VERSION#<semver>` |
  | Name reservation | `NAME#<app>` | `RESERVATION` |
  | Repository record | `REPO#<owner>/<name>` | `META` |

- [ ] **GSI1** (`GSI1PK = TEMPLATE#<name>#<semver>`) for the drift query *"which repos are
      behind the current template version?"* — define now; adding a GSI later means a backfill
- [ ] TTL on reservations so abandoned requests release their name automatically
- [ ] `ReserveNameUseCase` as a conditional `PutItem` on `attribute_not_exists(PK)` — name
      uniqueness as one atomic operation, not a read-then-write race

**Hands-on checks**
- [ ] Reserve the same name twice; catch `ConditionalCheckFailedException` and surface it as a
      domain error, not a leaked exception
- [ ] Write an item over 400KB and read the error
- [ ] Query with a small page size and walk `LastEvaluatedKey` to exhaustion
- [ ] Run one access pattern as Query and as Scan; compare consumed capacity in the response

---

## B4 — S3 · `Domain 1 + 2`

**Exam topics:** versioning; lifecycle rules and storage classes; **presigned URLs** (and that
their permissions are the signer's); multipart upload and when it is required; encryption
SSE-S3 / SSE-KMS / SSE-C / client-side; bucket policies vs IAM vs ACLs; Block Public Access;
event notifications; strong read-after-write consistency; byte-range fetches.

**Build**
- [ ] `ITemplateBundleStore` → S3 adapter fetching a bundle by `(template, version)`
- [ ] `ITemplateRenderer` → Scriban adapter rendering **both file contents and file paths**
      (`{{name}}.csproj` must become `Payments.csproj`)
- [ ] `templates/dotnet-api/` carrying the full production shape from `CLAUDE.md`: service
      code, OTel pre-wired with the same resource attributes the Go services set,
      health/readiness endpoints, graceful shutdown, structured JSON logging, Dockerfile, k8s
      manifest, CI/CD workflows following the `ci-`/`cd-`/`ops-` convention, `CLAUDE.md`,
      README, Terraform stub, catalog metadata
- [ ] Lambdas read bundles **only from S3 by version**, never from the repo — this is what
      makes a scaffold reproducible

Defer `dotnet-consumer` and `dotnet-console` until `dotnet-api` works end to end.

**Hands-on checks**
- [ ] Enable versioning, overwrite a bundle, fetch the prior version by version ID
- [ ] Generate a presigned URL, use it unauthenticated, let it expire
- [ ] Add a lifecycle rule and confirm the transition config

---

## B5 — Secrets Manager, KMS, IAM, STS · `Domain 2`

Second-heaviest domain, and the GitHub App gives it a real use case rather than a contrived one.

**Exam topics:** **Secrets Manager vs Parameter Store** (cost, size, native rotation); rotation
with a Lambda; envelope encryption; customer-managed vs AWS-managed KMS keys; key policies vs
IAM policies vs grants; data key caching; `AssumeRole` and temporary credentials;
identity-based vs resource-based policies; policy evaluation and explicit deny; least privilege.

**Build**
- [ ] Customer-managed KMS key for the secret and the template bucket
- [ ] GitHub App private key in Secrets Manager; secret declared in `template.yaml`, **value
      placed manually once** — never in source, never in a template parameter
- [ ] GitHub App JWT → installation token exchange
- [ ] Fetch and **cache the secret at cold start**, not per invocation — a Secrets Manager call
      on every request is the classic Lambda mistake
- [ ] **One IAM role per function** in `template.yaml`, each granted only what that function
      touches. Never a shared "scaffolder role"

**Hands-on checks**
- [ ] Strip one permission from a function's role; parse the `AccessDenied` for which
      principal, action, and resource it names
- [ ] Store the same value in Parameter Store and Secrets Manager; compare
- [ ] Enable rotation and watch a rotation invocation run

---

## B6 — Step Functions · `Domain 1`

**Exam topics:** Amazon States Language; state types (Task, Choice, Parallel, Map, Wait, Pass,
Succeed, Fail); `Retry` with backoff and `Catch`; predefined error names (`States.TaskFailed`,
`States.Timeout`, `States.ALL`); `InputPath` / `Parameters` / `ResultPath` / `OutputPath`; the
three service integration patterns (**Request Response**, **Run a Job `.sync`**, **Wait for
Callback `.waitForTaskToken`**); **Standard vs Express** (duration, execution semantics,
pricing, history); the 256KB payload limit; nested executions.

**Build**
- [ ] `AWS::Serverless::StateMachine` chaining `ReserveName → CreateRepository → PushScaffold
      → InjectInfraOutputs → ConfigureCiCd → RegisterRepository`, with `Catch → Compensate`
- [ ] `CreateRepositoryUseCase` and `PushScaffoldUseCase` (create tree + commit, not
      file-by-file)
- [ ] `InjectInfraOutputsUseCase` against a fixture payload
- [ ] `ConfigureCiCdUseCase` — repo secrets, branch protection, CODEOWNERS
- [ ] `RegisterRepositoryUseCase` — write the `REPO#` item and its GSI1 keys
- [ ] Run `CreateRepository` and the stubbed infra step in a `Parallel` state. Creating a repo
      does not depend on infrastructure existing; only `InjectInfraOutputs` needs both.
      Serializing them makes a developer wait for a multi-minute Terraform run before seeing
      their repository, and "time to first commit" is the metric this platform is judged on

**Hands-on checks**
- [ ] Read a failed execution in the console and find the exact failing state
- [ ] Exceed the 256KB payload limit deliberately and see how it surfaces
- [ ] Build the same flow as Standard and as Express; compare history and cost characteristics

---

## B7 — API Gateway *(optional)* · `Domain 1 + 2`

Worth building only if you want API Gateway hands-on beyond the Terraform module already
fronting the Go API.

**Exam topics:** REST vs HTTP vs WebSocket APIs; Lambda proxy vs non-proxy integration; stages
and stage variables; **usage plans and API keys**; throttling and quotas; Cognito authorizers
vs Lambda authorizers vs IAM auth; request validation; mapping templates; caching; CORS.

**Build**
- [ ] Read-only template catalog API: `GET /templates`, `GET /templates/{name}/versions`.
      Read-only keeps the single-write-entry-point rule intact — provisioning still goes
      through the Go API only
- [ ] Cognito authorizer reusing the existing user pool

**Hands-on checks**
- [ ] Attach a usage plan and get throttled deliberately
- [ ] Enable caching and watch the hit rate
- [ ] Break the authorizer; read the 401 vs 403 distinction

---

## B8 — EventBridge & SNS *(optional)* · `Domain 1`

The messaging gap: SQS is already covered by the Go services; EventBridge and SNS are not.

**Exam topics:** EventBridge custom buses, rules, event patterns vs schedules, targets, archive
and replay, DLQs on targets; SNS topics, fanout, **subscription filter policies**, FIFO topics,
message attributes; choosing between SNS, SQS, and EventBridge.

**Build**
- [ ] Emit `ScaffoldCompleted` / `ScaffoldFailed` to a custom bus at the end of the state machine
- [ ] SNS topic subscribed for notifications

**Hands-on checks**
- [ ] Write an event pattern matching only failures
- [ ] Add a filter policy so one subscriber sees only one event type
- [ ] Archive and replay an event

---

## B9 — Deployment, versions & aliases · `Domain 3`

**Exam topics:** Lambda **versions and aliases**; weighted alias routing; `AutoPublishAlias`;
CodeDeploy deployment configurations (`Canary`, `Linear`, `AllAtOnce`); pre/post-traffic hooks;
automatic rollback on alarm; blue/green vs rolling vs immutable; CodeBuild buildspec and
artifacts; CodePipeline stages.

**Build**
- [ ] `AutoPublishAlias: live` plus `DeploymentPreference: Canary10Percent5Minutes`, gated on
      the B10 alarms, so a bad deploy rolls back through CodeDeploy automatically
- [ ] **CI** — a **separate `dotnet` job** in `.github/workflows/ci-services-test.yml`. Do
      *not* add `scaffolder` to the existing `matrix: [api, provisioner]`; that matrix is
      Go-specific (`setup-go`, `go-version-file`, `gofmt`, `go vet`). Mirror its structure:
      build, format check, test with coverage, coverage into `$GITHUB_STEP_SUMMARY`
- [ ] **CD** — `.github/workflows/cd-scaffolder.yml` following `cd-provisioner.yml`: the
      `# PURPOSE / TRIGGER / AUTH / EFFECT / REQUIRES / DOCS` header block, SHA-pinned actions,
      `concurrency: {group: deploy-scaffolder, cancel-in-progress: false}`,
      `permissions: {id-token: write, contents: read}`, and the existing
      `./.github/actions/aws-oidc-login` composite. Steps are `sam build` + `sam deploy` — no
      Docker, ECR, or kubectl
- [ ] CI job packaging `templates/*` into versioned bundles, uploading to S3, recording version
      + checksum in DynamoDB

**Repo housekeeping** — real conventions here, easy to miss
- [ ] `.github/dependabot.yml` — add a `nuget` ecosystem entry for `/services/scaffolder`,
      grouped weekly, matching the existing `gomod` block
- [ ] `docs/adr/0004-sam-for-serverless-terraform-for-shared-infra.md` using
      `docs/adr/template.md`; its `## Alternatives considered` records why the *shared* state
      machine stays in Terraform while the scaffolder's own machine is SAM
- [ ] Add the ADR row to the index table in `docs/adr/README.md`
- [ ] Drop the **"Status: design only"** banner from `CLAUDE.md`
- [ ] Update the root `CLAUDE.md` Scaffolder entry

**No Terraform component is added.** SAM owns everything here, so `.github/infra-components.yml`,
the `case` in `_terraform.yml`, and the dropdown in `ops-infra-component.yml` stay untouched.
That three-place edit applies only to Terraform components — noted so it isn't done by reflex.

**Hands-on checks**
- [ ] Deploy a knowingly-broken version; watch the canary roll back
- [ ] Shift alias weights by hand and observe the traffic split
- [ ] Invoke a specific version directly by ARN

---

## B10 — Observability & troubleshooting · `Domain 4`

Study continuously from B1 onward, not at the end.

**Exam topics:** CloudWatch log groups, streams, retention; **Logs Insights** queries; metric
filters; **EMF**; custom metrics and dimensions; alarms including composite alarms and
missing-data treatment; X-Ray segments, subsegments, **annotations vs metadata**, sampling
rules, service map; interpreting Lambda `Duration` / `Init Duration` / throttles / concurrent
executions.

**Build**
- [ ] **ADOT Lambda layer, not the X-Ray SDK.** ADOT speaks W3C trace context, which is what
      the Go services propagate, so a request stays one distributed trace once the chain is
      connected; X-Ray's native header format would break that continuity
- [ ] Export to X-Ray and CloudWatch directly — the OTel Collector runs in-cluster and is
      unreachable from Lambda. Do **not** VPC-attach the functions just for telemetry
- [ ] Metrics via **CloudWatch EMF**
- [ ] X-Ray active tracing on the state machine
- [ ] Alarms on errors, throttles, and duration — these gate the B9 canary

**Hands-on checks**
- [ ] Write a Logs Insights query finding all failed scaffolds in the last day
- [ ] Add an X-Ray annotation and filter traces by it; try the same with metadata and see why
      you can't
- [ ] Read a cold start on the service map

---

## Cross-cutting: idempotency & compensation

Not a standalone block — it belongs to every handler.

- [ ] **Every state transition is a conditional write** on the expected current status. Step
      Functions retries plus at-least-once delivery mean handlers *will* run twice; without
      this the failure mode is a duplicate GitHub repository
- [ ] `CompensateUseCase` deletes the repository and releases the reservation, in reverse order
- [ ] **Test the compensation path as thoroughly as the happy path** — it runs rarely, which is
      exactly why it rots

---

## Verification

Per block:

```bash
cd services/scaffolder
dotnet build && dotnet test        # domain + application, no AWS
sam build
sam local invoke ReserveName -e events/reserve-name.json    # needs Docker
```

Integration tests run adapters against LocalStack (DynamoDB, S3, Secrets Manager) and the
throwaway GitHub org from B0.

**End-to-end, once B6 lands** — start one state machine execution and confirm:

- [ ] Template bundle exists in S3 with its `TEMPLATE#` item in DynamoDB
- [ ] Execution completes, every state green in the console
- [ ] In the test org: repo exists, renders with the right name, CI workflow present and green
      on first push, branch protection and CODEOWNERS applied
- [ ] The `REPO#` item exists with correct GSI1 keys, and GSI1 answers the drift query
- [ ] Re-running with an identical payload is a no-op — no duplicate repo, no second reservation
- [ ] Forcing a mid-run failure triggers `Compensate`, leaving no repository and no reservation
