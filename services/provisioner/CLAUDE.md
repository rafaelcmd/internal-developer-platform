# Provisioner Service

Go SQS consumer: polls the provisioning queue and (eventually) provisions cloud
resources from the messages the API publishes.

Go version: 1.25 (see `go.mod`). Entry point: `cmd/consumer/main.go`.

## Layout

```
cmd/consumer/main.go   - entry point: picks the transport, sets up telemetry
internal/consumer/      - the consume loops: kafka.go, sqs.go, shared metrics.go,
                          queue trace-context extraction (propagation.go)
internal/telemetry/    - OpenTelemetry setup (OTLP traces, metrics, logs)
internal/logger/       - logrus-backed JSON logger behind a small interface
infra/terraform/       - the EC2 host this runs on (standalone, not on EKS)
db/                    - RDS init
Dockerfile.dev, docker-compose.dev.yaml - local run (Kafka-based dev stack)
```

Runs standalone on its own EC2 instance (see `infra/terraform`), **not** on the
EKS cluster — so telemetry targets a Collector via env, not in-cluster DNS.

## Message transport

Chosen at startup: **Kafka when `KAFKA_BROKERS` is set** (local dev — never
touches AWS), else **SQS** (dev/prod, resolves the queue URL from Parameter
Store). Both loops live in `internal/consumer` and share the same spans +
counters; only the ack differs (Kafka offset commit vs SQS delete). The Kafka
`KAFKA_TOPIC` (default `resource-provisioning`) must match the API's.

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
