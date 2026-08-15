# Internal Developer Platform

Monorepo for an internal developer platform that provisions cloud resources.

## Architecture

Event-driven, multi-service platform on AWS (EKS, SQS, Cognito):

1. **API** (`/services/api`) — Go 1.25 REST API. Receives resource creation requests, publishes messages to SQS.
2. **Provisioner** (`/services/provisioner`) — Go 1.25 service. Consumes SQS messages and orchestrates fulfilment.
3. **Scaffolder** (`/services/scaffolder`) — .NET on Lambda. Owns the repository domain: creates GitHub repos from golden-path templates and wires their CI/CD. **Design only — no code yet.**

Message flow: API → SQS → Provisioner → Step Functions → task workers

Planned but not yet created: an **Infra Worker** (Go) that executes infrastructure-as-code as a
`.waitForTaskToken` task in the same state machine. Until it exists, the provisioner is still a
bare consume loop and no state machine is deployed.

## Conventions

- Each service has its own `CLAUDE.md` with service-specific details — read it before working on that service.
- When a change alters a service's architecture, commands, or conventions, update that service's CLAUDE.md in the same commit.
- Go services use standard `cmd/` and `internal/` layout.
- Infrastructure follows Terraform `modules/` + `live/` pattern. **Exception:** the scaffolder's own
  serverless resources are owned by SAM (`services/scaffolder/template.yaml`); Terraform keeps
  shared, long-lived infrastructure. See that service's CLAUDE.md for the boundary.
- Services own their own data. No service reads another service's table or database.
