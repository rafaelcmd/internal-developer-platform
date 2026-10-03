# AWS Infra Worker

Go worker that owns the **AWS half of the infrastructure domain**: it consumes
`ProvisionInfra` tasks from the scaffold state machine and provisions the AWS
resources they name. It is the first of the per-cloud infra workers described
in [ADR-0008](../../../docs/adr/0008-one-infra-worker-per-cloud-provider.md);
Azure and GCP get sibling workers under `services/infra-workers/`.

**It runs no Terraform yet.** Each task's resources are logged, the task is
reported to Step Functions with `SendTaskSuccess` and the result
`{"Provisioned": false, "Mode": "log-only", "ResourceCount": n}`, and the
message is deleted. `Provisioned: false` is deliberate: the execution succeeds,
and anything reading `$.infrastructure` can tell nothing was created.

Go version: 1.25 (see `go.mod`). Entry point: `cmd/worker/main.go`.

## Layout

```
cmd/worker/main.go   - entry point: telemetry, -file mode, queue resolution
internal/worker/     - the SQS loop, Handle() (the logging) and the callback
internal/task/       - the ProvisionInfra task message and Input.Partition()
internal/telemetry/  - OpenTelemetry setup, copied from the provisioner
internal/logger/     - logrus-backed logger, copied from the provisioner
testdata/            - a sample task message, used by the tests and -file
Dockerfile           - multi-stage build onto distroless/static
```

## Where it runs

- **Infrastructure:** `infra/live/infra_worker_aws/dev` owns the task queue, its
  DLQ and the IRSA role + ServiceAccount `internal-developer-platform-infra-worker-aws`.
  The role can consume that queue and answer Step Functions callbacks, nothing
  more.
- **Workload:** `k8s/infra-worker-aws/deployment.yaml` (default namespace,
  Fargate), deployed by `cd-infra-worker-aws.yml`, which builds the image as
  `infra-worker-aws-<sha>` in the shared ECR repo.
- **Telemetry:** OTLP to the in-cluster OTel Collector, which ships logs, traces
  and metrics to Datadog under `service:infra-worker-aws`. Every log carries
  `request_id`, the key that ties it to the API's and the provisioner's logs for
  the same request. The trace does not cross Step Functions, so the worker's
  spans start a new trace.

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
  policy moves it to the dead-letter queue instead of losing it.
- **A callback that fails transiently leaves the message on the queue**, and
  the redelivery reports again under the same token.
- **A token Step Functions no longer accepts** (`TaskTimedOut`,
  `TaskDoesNotExist`, `InvalidToken`) gets the message deleted: no redelivery
  could answer it.
- **Resources for another provider are logged as warnings and never
  provisioned.** Routing by `cloud_provider` belongs to the control plane; the
  state machine does not split by provider yet, so the worker sees every
  resource of a request.

## Running

Without AWS, log a single message from a file:

```bash
go run ./cmd/worker -file testdata/provision-infra.json
```

Against a real queue, set `TASK_QUEUE_NAME` (resolved with `GetQueueUrl`) and the
usual AWS SDK credential environment; the worker long-polls until
SIGINT/SIGTERM. `OTEL_EXPORTER_OTLP_ENDPOINT` turns on telemetry export; unset,
logs only go to stdout.

## Commands

```bash
go build ./...   # build
go test ./...    # test
docker build -t infra-worker-aws .
```
