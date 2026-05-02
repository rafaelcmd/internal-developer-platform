# Internal Developer Platform

Monorepo for an internal developer platform that provisions cloud resources and tracks their costs.

## Architecture

Event-driven, multi-service platform on AWS (ECS, SQS, Cognito):

1. **API** (`/api`) — Go 1.24 REST API. Receives resource creation requests, publishes messages to SQS.
2. **Cost Manager** (`/services/cost-manager`) — Clojure 1.12 service. Consumes SQS messages and tracks costs across AWS/GCP/Azure.
3. **Provisioner** (`/services/provisioner`) — Go 1.22 service. Provisions cloud resources from SQS messages.

Message flow: API → SQS → Cost Manager / Provisioner

## Tech Stack

- **Languages:** Go (API, Provisioner), Clojure (Cost Manager)
- **Infra:** AWS ECS, Terraform (`/infra`), Kubernetes (`/k8s`)
- **Messaging:** AWS SQS, Kafka (local dev)
- **Observability:** Datadog, AWS X-Ray
- **CI/CD:** GitHub Actions (`.github/workflows/`)
- **Auth:** AWS Cognito

## Common Commands

### API (Go)
```bash
cd api && go run cmd/api/main.go    # run
cd api && go test ./...             # test
```

### Cost Manager (Clojure)
```bash
cd services/cost-manager && clojure -M -m cost-manager.core   # run
cd services/cost-manager && clojure -M:test                    # test
```

### Local Development
```bash
docker compose -f docker-compose.dev.yaml up   # Kafka + Zookeeper + services
```

## Project Layout

```
api/                  - Go REST API service
services/
  cost-manager/       - Clojure cost tracking service
  provisioner/        - Go resource provisioner
infra/                - Terraform modules and live config
k8s/                  - Kubernetes manifests
k6/                   - Load testing scripts
.github/workflows/    - CI/CD pipelines
```

## Conventions

- Each service has its own `CLAUDE.md` with service-specific details — read it before working on that service.
- Go services use standard `cmd/` and `internal/` layout.
- Infrastructure follows Terraform `modules/` + `live/` pattern.
