# ADR-0008: One infra worker per cloud provider

- **Status:** Proposed
- **Date:** 2026-10-03
- **Deciders:** Rafael Costa
- **Related:** ADR-0004 (Scaffolder runs as a container on EKS), ADR-0006
  (Step Functions orchestrates provisioning, workers execute it)

## Context

The platform is multi-cloud: a provision request's resources each carry a
`cloud_provider`, and the API accepts `AWS`, `Azure` and `GCP`. The platform's
own control plane runs on AWS (EKS, SQS, Step Functions), but the resources it
provisions for applications may live in any of the three.

ADR-0006 gives provisioning to an "infra worker" reached by one
`ProvisionInfra` callback task. It does not say whether one worker handles
every cloud, and the answer shapes credentials, deployables and the state
machine.

Two forces decide it. **Credentials:** a worker that can create resources in a
cloud holds powerful credentials for it. One worker holding all three would be
the most privileged workload on the platform, and a bug in its AWS path would
run with Azure and GCP credentials loaded. **Toolchain:** each cloud has its own
SDK, Terraform providers, state backend and failure modes, which change
independently of each other.

## Decision

We run **one infra worker per cloud provider**, each its own Go module and
deployable under `services/infra-workers/<provider>`, with its own task queue
and its own identity. The AWS worker (`services/infra-workers/aws`) is first.

- **The control plane routes by `cloud_provider`.** A worker receives only its
  provider's resources; one that receives a foreign resource reports it and
  does not provision it.
- **Every worker speaks the same task contract**: the `ProvisionInfra` message
  the state machine defines, so the control plane treats workers
  interchangeably apart from which queue it sends to.
- **Every worker is still a container on EKS**, as the root conventions
  require. Workers for other clouds reach them through workload identity
  federation from their Kubernetes service account, not stored keys.

This ADR does not fix how the state machine fans out to several workers
(a branch per provider, or a `Map` over resources grouped by provider). That is
decided when the second worker exists and there is something to fan out to.

## Consequences

- Each worker's credentials cover one cloud, and a compromise or bug is
  contained to it.
- Adding a provider is a new worker, queue and identity; no existing worker
  changes.
- The task contract is duplicated in every worker, in the same way the request
  contract is duplicated between the API and the provisioner, and changes to it
  touch every worker.
- One request can now span several workers, so partial success is possible: the
  AWS resources exist and the GCP ones failed. Compensation across workers is a
  state-machine concern ADR-0006's saga has to grow into.

## Alternatives considered

- **One infra worker for all clouds.** Fewer deployables, but it concentrates
  every cloud's credentials in one process and couples three independently
  changing toolchains into one release.
- **One worker per resource type** (a database worker, a bucket worker). Splits
  along the wrong axis: credentials and Terraform state are per cloud, so every
  type-worker would still need all three clouds' credentials.

## When to revisit

If a second provider's worker turns out to be mostly a copy of the AWS one with
a different Terraform provider, a shared library or a single binary selected by
configuration (still deployed once per cloud, with one cloud's credentials) may
be cheaper than separate modules.
