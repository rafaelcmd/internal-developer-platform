# Internal Developer Platform

> A cloud-native, event-driven platform that lets engineering teams self-service cloud
> infrastructure — provisioning resources on demand while tracking their cost in real time.

Built as a polyglot microservices system on AWS, this project demonstrates production-grade
patterns in distributed systems design: asynchronous messaging, service decoupling,
infrastructure-as-code, and multi-cloud cost governance.

---

## Why this project

Platform engineering teams spend enormous effort giving developers a paved road to cloud
resources without sacrificing control or visibility. This IDP tackles that problem end to end:

- **Self-service provisioning** — developers request resources through a single REST API instead of filing tickets or writing Terraform by hand.
- **Event-driven decoupling** — the API never blocks on slow cloud operations; work is handed off through a durable message queue.
- **Cost accountability** — every provisioned resource is tracked for spend across AWS, GCP, and Azure, so cost is a first-class signal, not an afterthought.

---

## Architecture

An event-driven, polyglot system designed for resilience and independent scaling.

```
                         ┌──────────────────┐
   Developer ──HTTP──▶   │       API        │   (Go 1.24)
                         │  REST interface  │
                         └────────┬─────────┘
                                  │ publish
                                  ▼
                         ┌──────────────────┐
                         │     AWS SQS      │   durable message queue
                         └────┬────────┬────┘
                     consume  │        │  consume
                              ▼        ▼
              ┌────────────────┐    ┌────────────────────┐
              │  Provisioner   │    │   Cost Manager     │
              │   (Go 1.22)    │    │  (Clojure 1.12)    │
              │ creates cloud  │    │ tracks spend across│
              │   resources    │    │  AWS / GCP / Azure │
              └────────────────┘    └────────────────────┘
```

**Message flow:** `API → SQS → Provisioner / Cost Manager`

Decoupling the write path (API) from the workers (Provisioner, Cost Manager) via SQS means each
service scales, deploys, and fails independently — a core tenet of reliable distributed systems.

---

## Tech Stack

| Domain            | Technologies                                              |
|-------------------|-----------------------------------------------------------|
| **Languages**     | Go (API, Provisioner), Clojure (Cost Manager)             |
| **Compute**       | AWS EKS on Fargate, Kubernetes                            |
| **Messaging**     | AWS SQS (production), Kafka (local dev)                   |
| **Infra as Code** | Terraform (`modules/` + `live/` pattern)                 |
| **Auth**          | AWS Cognito                                               |
| **Observability** | Datadog, AWS X-Ray                                        |
| **CI/CD**         | GitHub Actions                                            |

---

## Engineering Highlights

- **Polyglot by design** — Go for high-throughput, latency-sensitive services; Clojure for the data-oriented cost engine, showing the right tool for each job.
- **Asynchronous, at-least-once processing** built on SQS for durability and back-pressure tolerance.
- **Infrastructure as code** — the entire AWS footprint (EKS, SQS, Cognito) is reproducible through Terraform.
- **Runs serverless-ly** on EKS + Fargate — no node management, pay-per-pod.
- **First-class observability** with Datadog metrics and distributed tracing via AWS X-Ray.

---

## Repository Layout

```
api/                  Go REST API — accepts requests, publishes to SQS
services/
  cost-manager/       Clojure service — consumes SQS, tracks multi-cloud cost
  provisioner/        Go service — provisions cloud resources from SQS
infra/                Terraform modules and live environments
k8s/                  Kubernetes manifests
k6/                   Load-testing scripts
.github/workflows/    CI/CD pipelines
```

---

## Running Locally

Spin up the full stack (Kafka + Zookeeper + services) with Docker Compose:

```bash
docker compose -f docker-compose.dev.yaml up
```

Run individual services:

```bash
# API (Go)
cd api && go run cmd/api/main.go

# Cost Manager (Clojure)
cd services/cost-manager && clojure -M -m cost-manager.core
```

Run the test suites:

```bash
cd api && go test ./...
cd services/cost-manager && clojure -M:test
```
