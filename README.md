# Internal Developer Platform

> A cloud-native, event-driven platform that lets engineering teams self-service cloud
> infrastructure — provisioning resources on demand while tracking their cost in real time.

Built as a microservices system on AWS, this project demonstrates production-grade
patterns in distributed systems design: asynchronous messaging, service decoupling,
and infrastructure-as-code.

---

## Why this project

Platform engineering teams spend enormous effort giving developers a paved road to cloud
resources without sacrificing control or visibility. This IDP tackles that problem end to end:

- **Self-service provisioning** — developers request resources through a single REST API instead of filing tickets or writing Terraform by hand.
- **Event-driven decoupling** — the API never blocks on slow cloud operations; work is handed off through a durable message queue.
- **Cost accountability** — every provisioned resource is tracked for spend across AWS, GCP, and Azure, so cost is a first-class signal, not an afterthought.

---

## Architecture

An event-driven system designed for resilience and independent scaling.

```
                         ┌──────────────────┐
   Developer ──HTTP──▶   │       API        │   (Go 1.24)
                         │  REST interface  │
                         └────────┬─────────┘
                                  │ publish
                                  ▼
                         ┌──────────────────┐
                         │     AWS SQS      │   durable message queue
                         └────────┬─────────┘
                                  │ consume
                                  ▼
                         ┌────────────────┐
                         │  Provisioner   │
                         │   (Go 1.25)    │
                         │ creates cloud  │
                         │   resources    │
                         └────────────────┘
```

**Message flow:** `API → SQS → Provisioner`

Decoupling the write path (API) from the worker (Provisioner) via SQS means each
service scales, deploys, and fails independently — a core tenet of reliable distributed systems.

---

## Tech Stack

| Domain            | Technologies                                              |
|-------------------|-----------------------------------------------------------|
| **Languages**     | Go (API, Provisioner)                                     |
| **Compute**       | AWS EKS on Fargate, Kubernetes                            |
| **Messaging**     | AWS SQS (production), Kafka (local dev)                   |
| **Infra as Code** | Terraform (`modules/` + `live/` pattern)                 |
| **Auth**          | AWS Cognito                                               |
| **Observability** | Datadog, AWS X-Ray                                        |
| **CI/CD**         | GitHub Actions                                            |

---

## Engineering Highlights

- **Asynchronous, at-least-once processing** built on SQS for durability and back-pressure tolerance.
- **Infrastructure as code** — the entire AWS footprint (EKS, SQS, Cognito) is reproducible through Terraform.
- **Runs serverless-ly** on EKS + Fargate — no node management, pay-per-pod.
- **First-class observability** with Datadog metrics and distributed tracing via AWS X-Ray.

---

## Repository Layout

```
api/                  Go REST API — accepts requests, publishes to SQS
services/
  provisioner/        Go service — provisions cloud resources from SQS
infra/                Terraform modules and live environments
k8s/                  Kubernetes manifests
k6/                   Load-testing scripts
.github/workflows/    CI/CD pipelines
```

---

## Running Locally

Spin up the full stack (Kafka + Zookeeper + services + OTel Collector) with Docker Compose:

```bash
docker compose -f docker-compose.dev.yaml up
```

**Observability locally:** an OpenTelemetry Collector receives OTLP from the
services and scrapes the API's `/metrics`. Inspect the pipeline with:

```bash
docker compose -f docker-compose.dev.yaml logs -f otel-collector  # telemetry (debug exporter)
curl http://localhost:8889/metrics                                # collected metrics
```

Run individual services:

```bash
# API (Go)
cd api && go run cmd/server/main.go

# Provisioner (Go)
cd services/provisioner && go run cmd/consumer/main.go
```

Run the test suites:

```bash
cd api && go test ./...
cd services/provisioner && go test ./...
```
