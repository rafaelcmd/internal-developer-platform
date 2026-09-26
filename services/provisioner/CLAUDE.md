# Provisioner Service

Go SQS consumer and the platform's **control plane**: it polls the provisioning
queue, decodes the request the API published, and splits it into the work each
downstream worker owns — the repository half for the scaffolder, the cloud
resources half for the (not yet built) infra worker.

The component also owns the **scaffold state machine** and the **request-state
table**, in `infra/live/provisioner/dev`. Those are infrastructure, not code in
this directory: the machine exists and can be started by hand, but the consumer
does not call `StartExecution` yet. See [ADR-0006](../../docs/adr/0006-step-functions-as-provisioning-orchestrator.md)
and `infra/live/provisioner/dev/README.md`.

Go version: 1.25 (see `go.mod`). Entry point: `cmd/consumer/main.go`.

## Layout

```
cmd/consumer/main.go   - entry point: picks the transport, sets up telemetry
internal/consumer/      - the consume loops: kafka.go, sqs.go, shared metrics.go,
                          queue trace-context extraction (propagation.go), and
                          dispatch.go - the split, shared by both loops
internal/provision/    - the wire contract the API publishes, and Request.Split()
internal/telemetry/    - OpenTelemetry setup (OTLP traces, metrics, logs)
internal/logger/       - logrus-backed JSON logger behind a small interface
db/                    - RDS init
Dockerfile.dev, docker-compose.dev.yaml - local run (Kafka-based dev stack)
```

Runs on the EKS cluster alongside the API: `k8s/provisioner/deployment.yaml`
(default namespace, Fargate), deployed by the `cd-provisioner.yml` workflow
(build + push to the shared ECR repo as immutable `provisioner-<sha>` — also
tagged `provisioner-latest` for convenience — then apply; the sha tag makes the
apply itself roll the Deployment). AWS access (SQS consume, SSM read) comes
from the IRSA-annotated
ServiceAccount `internal-developer-platform-provisioner`
(`infra/live/provisioner/dev/irsa.tf` — the service owns its own identity
stack; the queue and cluster it uses belong to the `api` component). The
Deployment sets
`OTEL_EXPORTER_OTLP_ENDPOINT` to the in-cluster OTel Collector Service, which
is what ships logs/traces/metrics to Datadog. (Previously ran on a standalone
EC2 host with no Collector route, so its telemetry never left the box.)

## Message transport

Chosen at startup: **Kafka when `KAFKA_BROKERS` is set** (local dev — never
touches AWS), else **SQS** (dev/prod, resolves the queue URL from Parameter
Store: `PROVISIONER_QUEUE_PARAM_KEY`, default
`/INTERNAL_DEVELOPER_PLATFORM/PROVISIONER_QUEUE_URL` — the key the SQS
Terraform module publishes and the API also reads). Both loops live in `internal/consumer` and share the same spans +
counters; only the ack differs (Kafka offset commit vs SQS delete). The Kafka
`KAFKA_TOPIC` (default `resource-provisioning`) must match the API's.

## The split

`provision.Request` is the message the API publishes: one `application` and its
`resources`, under one `request_id`. `Request.Split()` divides it into
`ScaffoldWork` and `InfraWork`, and `consumer.Dispatch` is what both consume
loops call to do it.

The contract is **duplicated** from `services/api/internal/domain/model` rather
than imported. They are separate modules and separate deployables, and a shared
struct would make a field rename in one a compile break in the other — the
coupling a queue exists to remove. The cost is that the two definitions have to
change together, and the comment on each says so.

Two details that matter downstream:

- `request_id` goes into **both** halves. The scaffolder keys its name
  reservation and repository claim on it, so dropping it from either side breaks
  idempotency there with no symptom until a retry.
- `ScaffoldWork.Owner` is the **team**, not the GitHub organization. The
  scaffolder takes the org from its own `GITHUB_ORG` config precisely so a queue
  message cannot choose where it writes.

**Nothing is dispatched yet.** `Dispatch` logs both halves and the message is
acknowledged. The state machine now exists, so what is missing is the call:
`StartExecution` belongs exactly where that logging is.

When it is written, three things are already decided by the infrastructure:

- **The execution input is the request message, unchanged.** The machine reads
  `request_id`, `application.*` and `resources` in the same snake_case shape the
  API publishes, so the consumer passes through what it parsed rather than
  translating. `Split()` stays what it is: the control plane's statement of who
  owns which half, and the thing the log fields are built from.
- **Execution identity comes from `request_id`.** A deterministic execution name
  makes a redelivered SQS message collide with `ExecutionAlreadyExists` instead
  of starting a second saga. That is the idempotency mechanism; the request
  table is not.
- **The state machine is the single writer of a request row.** The consumer
  reads it (`dynamodb:GetItem` only) and never writes it.

The ARN and the table name are resolved at startup from
`/idp/provisioner/<env>/scaffold_state_machine_arn` and
`/idp/provisioner/<env>/requests_table_name`, the same way the queue URL is.

## Observability

Fully OpenTelemetry and vendor-agnostic — the service emits OTLP and never names
a backend; the OTel Collector decides where it lands (Datadog today). Replaced
the former AWS X-Ray SDK.

- **Traces:** `internal/telemetry` builds an OTLP/gRPC TracerProvider and installs
  W3C propagators. Each consumed message gets a `ProcessMessage` span; the SQS
  path adds `PollSQSMessages` / `GetSQSQueueURL` and instruments AWS SDK calls
  with `otelaws` middleware (replaces `xray.Client`). `ProcessMessage` **continues
  the API's trace**: the consumer extracts the W3C trace context the API injected
  into each message (SQS message attributes / Kafka headers, via
  `consumer/propagation.go`) and starts the span from it, so one provision request
  is a single distributed trace across API → queue → provisioner and both services'
  logs share its `trace_id`.
- **Metrics:** OTLP/gRPC MeterProvider with counters
  `provisioner.messages.received|processed|failed`.
- **Logs:** structured **logrus** behind a small `Logger` interface
  (`internal/logger`) — the same package shape the API uses, so both Go services
  log with one API and one set of field conventions. logrus writes JSON to stdout
  unconditionally (local dev visibility + host stdout archive); an OTLP bridge hook
  (`otellogrus`), returned by `telemetry.Setup` and attached at logger construction,
  mirrors every entry onto an OTLP/gRPC log pipeline, so logs ride the same
  vendor-agnostic Collector seam as traces/metrics (Datadog today). Call
  `log.WithContext(ctx)` on every log so the hook stamps the message's trace/span
  IDs and lines correlate with traces (and with the API's logs — same `trace_id`).
  The hook is nil in local Kafka dev — `telemetry.Setup` returns it only when
  `OTEL_EXPORTER_OTLP_ENDPOINT` is set — so logs there just print to stdout.
- **Config:** the standard `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_
  INSECURE` env vars drive export. **When the endpoint is unset, telemetry setup
  is a no-op** (local Kafka dev has no Collector) — instrumentation calls become
  cheap no-ops via OTel's global default providers. `SERVICE_VERSION` /
  `ENVIRONMENT` feed the OTel resource (→ Datadog service/version/env tags).

The root context cancels on SIGINT/SIGTERM so the loop drains and the batch
exporters flush on shutdown.

## Commands

```bash
go build ./...   # build
go test ./...    # test
docker compose -f ../../docker-compose.dev.yaml up   # local Kafka dev stack
```
