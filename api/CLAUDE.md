# API Service

Go REST API and entry point of the platform: it receives resource provisioning
requests, authenticates users against Cognito, and publishes provision messages
to SQS for the downstream services (provisioner, cost-manager).

Go version: 1.25 (see `go.mod`). Entry point: `cmd/server/main.go`.

## Commands

```bash
make build          # go build -o bin/server ./cmd/server
make test           # go test ./...
make run            # build + run
make swagger-validate  # validate docs/swagger.yaml (needs swagger-cli)
docker compose -f docker-compose.dev.yaml up   # containerized local run
```

## Architecture

Hexagonal (ports & adapters) with a composition root:

```
cmd/server/main.go              - entry point
internal/
  bootstrap/application.go      - composition root: ALL dependency wiring happens here
  domain/
    model/, valueobjects/, errors/
    ports/inbound/              - service interfaces (ResourceService, AuthService)
    ports/outbound/             - driven-side interfaces (ResourcePublisher, AuthProvider, IdempotencyStore)
  application/service/          - use-case implementations of the inbound ports
  adapters/
    inbound/http/               - router, handlers, middleware (request counter, recovery,
                                  request context, standard headers, CORS, idempotency)
    outbound/sqs/               - ResourcePublisher -> SQS
    outbound/cognito/           - AuthProvider -> Cognito
    outbound/idempotency/       - IdempotencyStore -> Redis
  infrastructure/               - AWS SDK clients, Parameter Store, Redis client
  telemetry/                    - OTel MeterProvider + Prometheus exporter
  config/                       - env-var config (12-factor), defaults + validation
  logger/                       - logrus-backed JSON logger behind a small interface
  server/                       - HTTP server with graceful shutdown
  test/mocks/                   - hand-written fakes for ports
```

Dependency rule: `domain` depends on nothing; `application` depends on domain
ports; `adapters` implement ports; only `bootstrap` knows concrete types.
When adding a dependency, wire it in `bootstrap/application.go`, not inside
handlers or services.

## Routes

- `POST /v1/provision` — publish a resource request to SQS; deduped by the
  idempotency middleware when an `X-Idempotency-Key` header is sent (Redis-backed).
- `POST /v1/auth/signup | signin | confirm` — Cognito flows.
- `GET /v1/health` — liveness.
- `GET /metrics` — Prometheus scrape endpoint (unversioned by convention).
- `GET /v1/swagger/` — Swagger UI. The spec (`docs/swagger.yaml`) is
  hand-maintained, not generated — update it when routes change.

## Configuration

All config comes from env vars (`internal/config/config.go`); runtime values
(SQS queue URL, Cognito client ID, Redis address) are loaded from AWS Parameter
Store at boot. Key vars:

- `ENVIRONMENT` — `dev` (default), `prod`, or `local` (see below)
- `PORT` (default 8080), `LOG_LEVEL`, `SERVICE_NAME`
- `ENABLE_TRACING` — Datadog APM tracer (default true, skipped in local mode)
- `REDIS_ADDR` — overrides Parameter Store for local compose; empty + no param
  key means the idempotency layer is silently disabled

## Local mode

`ENVIRONMENT=local` boots the API with no AWS, Parameter Store, Redis, or
Datadog. Only `/metrics`, `/v1/health`, and swagger are functional; resource and
auth routes return 500 because their services are nil. Used by
`docker-compose.dev.yaml`.

## Observability

All three signals are OpenTelemetry and vendor-agnostic: the app emits to an OTel
Collector (OTLP) / Prometheus and knows nothing about the backend. Datadog is one
exporter behind the Collector, not a dependency in this code. The shared OTel
resource (`internal/telemetry/resource.go`) sets `service.name` / `service.version`
/ `deployment.environment` from `SERVICE_NAME` / `SERVICE_VERSION` / `ENVIRONMENT`,
which Datadog maps onto its service/version/env unified tags. All OTLP export is
gated on `ENABLE_TRACING` and skipped in local mode (no Collector to receive it).

- **Metrics:** OpenTelemetry with a Prometheus exporter (`internal/telemetry`).
  The MeterProvider is registered as the OTel global in bootstrap, so
  instruments are created via `otel.Meter(...)` anywhere. Scraped at `/metrics`
  (pull) — in-cluster, the Collector's prometheus receiver scrapes it via the
  pod's `prometheus.io/scrape` annotations. Follow OTel semconv
  names/attributes (`semconv` v1.26.0) for new instruments.
  `RequestDurationMiddleware` records request latency on the
  `http.server.request.duration` Histogram (unit: seconds), labeled with method,
  matched route, and status code. It sits above the recovery layer so a recovered
  panic is timed and recorded as a 500. There is no separate request counter: the
  histogram's `_count` series already counts every request, so request rate is
  `rate(http_server_request_duration_seconds_count[...])`. The histogram's bucket
  boundaries are overridden to semconv seconds-scale values via a View in
  `internal/telemetry` (the SDK defaults are milliseconds-scale and would collapse
  every latency into one bucket). `ActiveRequestsMiddleware` (outermost) gauges
  in-flight requests on the `http.server.active_requests` UpDownCounter, labeled
  with method only (route/status are unknown while the request is still being
  served). Both middlewares skip the `/metrics` scrape endpoint (so Prometheus
  polling doesn't dominate the stats) and normalize the method label to a known
  set or `_OTHER` (so arbitrary request methods can't blow up cardinality).
- **Tracing:** OpenTelemetry SDK exporting spans over OTLP/gRPC to the Collector
  (`internal/telemetry/tracing.go`). The router is wrapped with `otelhttp` in
  bootstrap, which starts a server span per request from the propagated context;
  W3C trace-context + baggage propagators are installed globally. (Replaced the
  former `dd-trace-go` APM tracer.)
- **Logs:** logrus stays the logging API; an OTel bridge hook
  (`otellogrus`, wired in `internal/telemetry/logs.go`) mirrors every entry onto
  an OTLP/gRPC log pipeline to the Collector, carrying trace/span IDs from the
  entry context so logs correlate with traces. The hook is attached at logger
  construction via `logger.Config.Hooks`.
- **OTLP endpoint:** `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_INSECURE`
  (standard OTel env vars, read directly by the exporters) — not app config.

## Testing

- Standard `go test ./...`; tests use `testify/assert`, `httptest`, and the
  fakes in `internal/test/mocks` (no mock generation).
- HTTP-layer tests build routers via `NewRouterWithConfig` with nil handlers
  for routes they don't exercise.
