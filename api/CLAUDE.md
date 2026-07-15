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

- **Metrics:** OpenTelemetry with a Prometheus exporter (`internal/telemetry`).
  The MeterProvider is registered as the OTel global in bootstrap, so
  instruments are created via `otel.Meter(...)` anywhere. Follow OTel semconv
  names/attributes (`semconv` v1.26.0) for new instruments. Every request is
  counted on `http.server.requests` by `RequestCounterMiddleware` (outermost in
  the chain), labeled with method, matched route, and status code.
  `ActiveRequestsMiddleware` (alongside the counter) gauges in-flight requests on
  the `http.server.active_requests` UpDownCounter, labeled with method only
  (route/status are unknown while the request is still being served).
- **Tracing:** Datadog APM via `dd-trace-go` (not OTel), wrapped around the
  router in bootstrap.

## Testing

- Standard `go test ./...`; tests use `testify/assert`, `httptest`, and the
  fakes in `internal/test/mocks` (no mock generation).
- HTTP-layer tests build routers via `NewRouterWithConfig` with nil handlers
  for routes they don't exercise.
