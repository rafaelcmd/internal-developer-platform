# Internal Developer Platform

Monorepo for an internal developer platform that provisions cloud resources.

## Architecture

Event-driven, multi-service platform on AWS (EKS, SQS, Cognito):

1. **API** (`/api`) — Go 1.25 REST API. Receives resource creation requests, publishes messages to SQS.
2. **Provisioner** (`/services/provisioner`) — Go 1.25 service. Provisions cloud resources from SQS messages.

Message flow: API → SQS → Provisioner

## Conventions

- Each service has its own `CLAUDE.md` with service-specific details — read it before working on that service.
- When a change alters a service's architecture, commands, or conventions, update that service's CLAUDE.md in the same commit.
- Go services use standard `cmd/` and `internal/` layout.
- Infrastructure follows Terraform `modules/` + `live/` pattern.
