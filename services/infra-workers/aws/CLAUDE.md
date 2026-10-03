# AWS Infra Worker

Go worker that owns the **AWS half of the infrastructure domain**: it consumes
`ProvisionInfra` tasks from the scaffold state machine and provisions the AWS
resources they name. It is the first of the per-cloud infra workers described
in [ADR-0008](../../../docs/adr/0008-one-infra-worker-per-cloud-provider.md);
Azure and GCP get sibling workers under `services/infra-workers/`.

**It only logs today.** Each task's resources are logged and the message is
deleted. It runs no Terraform and never calls `SendTaskSuccess` or
`SendTaskFailure`, so a state machine pointed at it would wait out
`provision_infra_timeout_seconds`. That is why `infra_worker_task_queue_name`
stays null and the `ProvisionInfra` state stays a `Fail` state. There is no
queue, IRSA role, image, Kubernetes manifest or deploy workflow for it yet.

Go version: 1.25 (see `go.mod`). Entry point: `cmd/worker/main.go`.

## Layout

```
cmd/worker/main.go   - SQS long-poll loop, -file mode, and handle(): the logging
internal/task/       - the ProvisionInfra task message and Input.Partition()
testdata/            - a sample task message, used by the tests and -file
```

## The task contract

The message is shaped by the `ProvisionInfra` state in
`infra/live/provisioner/dev/state_machine.tf`, not by a Go type in another
module. The envelope (`Task`, `TaskToken`, `Input.RequestId`,
`Input.ApplicationName`) is PascalCase because the state machine writes it;
`Input.Resources` is the API's `resources` array passed through unchanged, so
it keeps the API's snake_case (`resource_type`, `cloud_provider`, ...). Change
`internal/task/task.go` and that state together.

- **`TaskToken` is never logged.** Anyone holding it can complete the task.
- **A message that fails to parse is not deleted**, so the queue's redrive
  policy moves it to a dead-letter queue instead of losing it.
- **Resources for another provider are logged as warnings and never
  provisioned.** Routing by `cloud_provider` belongs to the control plane, so
  one reaching this worker is a routing bug, not work.

## Running

Without AWS, log a single message from a file:

```bash
go run ./cmd/worker -file testdata/provision-infra.json
```

Against a real queue, set `TASK_QUEUE_URL` and the usual AWS SDK credential
environment; the worker long-polls until SIGINT/SIGTERM.

Logs are JSON from `log/slog` on stdout, with no OpenTelemetry pipeline yet.
When the worker is deployed it should adopt the provisioner's `internal/logger`
and `internal/telemetry` shape so its logs correlate with the rest of the
request's trace.

## Commands

```bash
go build ./...   # build
go test ./...    # test
```
