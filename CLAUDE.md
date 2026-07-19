# Internal Developer Platform

Monorepo for an internal developer platform that provisions cloud resources.

## Architecture

Event-driven, multi-service platform on AWS (EKS, SQS, Cognito):

1. **API** (`/api`) — Go 1.25 REST API. Receives resource creation requests, publishes messages to SQS.
2. **Provisioner** (`/services/provisioner`) — Go 1.25 service. Provisions cloud resources from SQS messages.

Message flow: API → SQS → Provisioner

## Tech Stack

- **Languages:** Go (API, Provisioner)
- **Infra:** AWS EKS on Fargate, Terraform (`/infra`), Kubernetes (`/k8s`)
- **Messaging:** AWS SQS, Kafka (local dev)
- **Observability:** Datadog, AWS X-Ray
- **CI/CD:** GitHub Actions (`.github/workflows/`)
- **Auth:** AWS Cognito

## Common Commands

### API (Go)
```bash
cd api && go run cmd/server/main.go    # run
cd api && go test ./...                # test
```

### Local Development
```bash
docker compose -f docker-compose.dev.yaml up   # Kafka + Zookeeper + services
```

## Project Layout

```
api/                  - Go REST API service
services/
  provisioner/        - Go resource provisioner
infra/                - Terraform modules and live config
k8s/                  - Kubernetes manifests
k6/                   - Load testing scripts
.github/workflows/    - CI/CD pipelines
```

## Conventions

- Each service has its own `CLAUDE.md` with service-specific details — read it before working on that service.
- When a change alters a service's architecture, commands, or conventions, update that service's CLAUDE.md in the same commit.
- Go services use standard `cmd/` and `internal/` layout.
- Infrastructure follows Terraform `modules/` + `live/` pattern.
