# ADR-0006: Step Functions orchestrates provisioning, workers execute it

- **Status:** Proposed
- **Date:** 2026-09-20
- **Deciders:** Rafael Costa
- **Related:** ADR-0004 (Scaffolder runs as a container on EKS), ADR-0007
  (Scaffolded applications resolve infrastructure by reference)

## Context

A provision request arrives at the API, goes onto SQS, and the provisioner
splits it into a repository half and a cloud-resources half
(`Request.Split()`). Past that point there was nothing: the provisioner logged
both halves and deleted the message. The scaffolder's `ReserveName` and
`CreateRepository` tasks existed and were reachable only by hand-seeding their
queues.

Finishing the control plane means deciding where the workflow's state lives,
and that is the whole decision. One request is a sequence of side effects
across two trust boundaries and one third party:

1. reserve the application name (scaffolder, own table);
2. create the GitHub repository (scaffolder, GitHub App key);
3. provision the cloud resources (infra worker, Terraform);
4. render the template into the repository and wire its CI/CD (scaffolder);
5. record the outcome.

Three forces shape it.

**The steps have very different durations.** A name reservation is one
conditional write. A repository creation is a GitHub API call that may sit
behind a rate limit. A Terraform run is minutes. Nothing may hold a thread, a
pod or a connection open across that spread.

**The process that starts the work is not the process that finishes it.** The
provisioner pod that consumed the SQS message has no useful relationship to the
scaffolder pod that creates the repository. If the provisioner were the
workflow's memory, restarting it would lose the answer to "was the repository
created?" and the only recovery would be to guess.

**Steps 2 and 3 fork, and the workflow joins after them.** Creating a repository
does not need infrastructure to exist, so the two run concurrently and a
developer sees their repository without waiting out a Terraform run: time to
first commit is the metric this platform is judged on.

What the repository *contains* is a separate question, and it is not
independent. An SQS consumer has to find its queue; a service with a datastore
has to find its database. Step 4 therefore needs both branches finished, which
makes it a join rather than a continuation of the repository branch. How much
actually has to cross that join is the subject of
[ADR-0007](0007-infrastructure-outputs-reach-applications-by-reference.md):
resolving infrastructure by reference rather than by injected value keeps the
join thin, but it does not remove it.

## Decision

We use an AWS Step Functions **STANDARD** state machine as the provisioning
orchestrator, and every worker step is an
`arn:aws:states:::sqs:sendMessage.waitForTaskToken` callback task. Step
Functions owns workflow state; workers own domain operations and are reached
only through the queues they already have.

The machine is defined in `infra/live/provisioner/dev/state_machine.tf` and
built by `infra/modules/aws/step_functions`. It is owned by the **provisioner**
component, not the scaffolder, because the provisioner is the control plane and
the workflow spans both workers. It consumes the scaffolder's task queue names
from the SSM parameters that stack already publishes.

The shape:

```
RecordRequestAccepted  (DynamoDB UpdateItem: RUNNING)
  └─ ReserveName                           .waitForTaskToken → scaffolder state queue
       └─ ScaffoldAndProvision (Parallel)
            ├─ CreateRepository            .waitForTaskToken → scaffolder github queue
            └─ ProvisionInfra              .waitForTaskToken → infra worker queue
                 └─ (or a Pass, when the request named no resources)
                 └─ RecordRequestSucceeded (DynamoDB UpdateItem: SUCCEEDED) → Succeed
  (Catch, any state) → RecordRequestFailed (DynamoDB UpdateItem: FAILED) → Fail
```

The steps after the fork are not in this definition yet: `PushScaffold`,
`InjectInfraOutputs` and the CI/CD wiring are still design only. They go between
the Parallel and `RecordRequestSucceeded`, and the shape already accommodates
them. The Parallel's `ResultPath` puts `$.results[0].repository` and
`$.results[1].infrastructure` into one object, which is exactly a join state's
input.

Four properties are load-bearing.

**Terminal request state is written by the machine, not by a worker.** A new
DynamoDB table in the provisioner stack holds one row per request
(`REQUEST#<request_id>` / `STATE`), carrying the execution ARN, the status and
the outcome. The state machine is its single writer, so there is no race
between the orchestrator and the consumer over who last described a request.

**Retries stop at the send.** A failed `SendMessage` means nothing ran and is
retried with full jitter. A `States.Timeout` on a callback is deliberately not
retried: SQS is already redelivering that message under the same token, and a
retry would put a second task in flight while the first is still queued, with
the abandoned copy dead-lettering on a token Step Functions no longer holds.
Domain failures reported through `SendTaskFailure` are terminal by definition.

**The timeout ladder is explicit.** Worker processing time < SQS visibility
timeout < visibility x redrive limit <= task timeout < execution timeout. The
third step is the one that is easy to get wrong: a task budget below the
queue's full redelivery run fails the execution while SQS is still retrying,
so the dead-letter alarm that explains the failure arrives after it.

**A request that names cloud resources fails while no infra worker exists.**
The `ProvisionInfra` state is a `Fail` state until
`infra_worker_task_queue_name` is set. Reporting success for a database nothing
created would be worse than failing.

There is no compensation state. The two tasks that exist today need none: the
name reservation expires on its own TTL, and `CreateRepository` adopts its own
repository on replay. Compensation becomes a real question when a step has an
irreversible effect that a later step can invalidate, which is the push and
CI/CD wiring still to be built.

## Consequences

**Easier.** Workflow state survives every process taking part in it, so "what
already happened to request X" is answerable from the execution history and
from one DynamoDB row rather than from logs. Adding a step is a state and a
worker registration, not a change to a consume loop. The execution graph with
X-Ray timings shows which step is slow without instrumenting anything. Failure
handling is declarative and reviewable in a diff.

**Harder.** The Amazon States Language is now a real part of the codebase, with
no type checking, no local execution, and an unhelpful class of runtime error:
a `$.` path that does not resolve fails the state with `States.Runtime`, which
no retry clears. The optional `description` field alone costs a Choice state
and two near-identical Task states. Tests for the workflow itself need an
account.

**Given up.** Startup latency and a little money: STANDARD charges per state
transition and keeps 90 days of history. At this volume it is cents, but the
per-transition model means a chatty workflow costs more than a coarse one, and
that pressure is real at enterprise scale.

**New dependency.** Step Functions is now in the path of every provision
request. Its regional availability is the platform's availability for anything
past the queue. Requests already accepted are safe, because SQS holds them
until an execution starts.

## Alternatives considered

- **Orchestration inside the provisioner process.** The consume loop calls each
  worker and tracks progress itself. Rejected: this is precisely the failure
  mode the design is meant to avoid. The provisioner becomes the implicit
  workflow database, and a crash between repository creation and infrastructure
  provisioning leaves no durable record of which happened. Rebuilding that
  guarantee means writing state transitions, retries, timeouts and a recovery
  scan by hand, which is Step Functions with worse operational tooling.

- **Choreography: each worker publishes an event, the next one subscribes.**
  Rejected for a workflow this small. It removes the orchestrator but puts the
  workflow's shape nowhere: no component knows what a complete request looks
  like, "which step is this request stuck on" has no single answer, and a
  parallel join has to be built out of state somebody owns anyway. Choreography
  earns its complexity when steps are owned by teams that must not coordinate;
  here they are two workers in one repository.

- **EXPRESS workflows.** Rejected on mechanics, not preference. Express caps
  executions at five minutes, does not support `.waitForTaskToken`, and keeps no
  durable execution history. All three are things this workflow depends on.

- **Step Functions with direct SDK integrations instead of callbacks.** The
  machine calls DynamoDB and GitHub itself, with no scaffolder. Rejected: the
  domain logic in `CreateRepositoryUseCase` (claim before create, so a replay
  can tell its own repository from someone else's) is not expressible in ASL,
  and it is the part that makes the step idempotent. The callback pattern is
  used exactly where a step needs judgment; the two DynamoDB writes that need
  none are direct integrations.

- **A self-hosted durable execution engine (Temporal, Cadence).** Better
  programming model, real testing story, no per-transition cost. Rejected on
  operational burden: it is a cluster plus a database to run, patch and back up,
  for a platform whose orchestration needs fit on one page.

## When to revisit

- A step needs a compensating action that the reservation TTL cannot express,
  which makes saga semantics explicit rather than implicit.
- State transition costs become visible on the bill, which means the workflow
  has grown chatty enough to be worth coarsening.
- The workflow needs branching that ASL expresses badly (dynamic fan-out over a
  resource list is the likely first case, and `Map` should be tried before the
  engine is blamed).
