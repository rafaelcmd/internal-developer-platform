# ADR-0003: Redis on ECS as the idempotency store

- **Status:** Accepted
- **Date:** 2026-05-03
- **Deciders:** Rafael Costa
- **Related:** ADR-0002 (API-edge idempotency layer)

## Context

ADR-0002 introduces an idempotency middleware that needs a storage backend
for keys, request hashes, and captured responses. The storage choice is a
separate decision from the contract because the contract should be stable
across storage migrations.

Functional requirements for the backend:

- **Centralized.** The API runs as multiple ECS Fargate replicas. A request
  may hit replica A, the retry may hit replica B; both must see the same
  idempotency state. Any per-replica store (in-memory, sidecar) silently
  fails this — and "silently" is the dangerous word, because the system
  *appears* to work when there is one replica.
- **Atomic reserve.** "Insert if absent, otherwise return existing" must
  be a single operation. Two concurrent requests with the same key must
  not both proceed to the handler.
- **TTL support.** Records expire after 24h (per ADR-0002). We don't want
  to write our own eviction sweeper.
- **Sub-millisecond reads.** Every keyed `POST /v1/provision` does at least
  one read on the storage backend. Latency of the backend is added directly
  to client latency.
- **Reachable from ECS Fargate** in private subnets. No public endpoints.

Non-functional context:

- This is a study/prep platform demonstrating production-grade design. Cost
  matters but isn't decisive at this scale.
- The platform already uses managed AWS services (SQS, Cognito, API Gateway,
  WAF). Adding a self-managed component is a deliberate divergence from
  that pattern.
- Single-developer ops capacity. Whatever we pick, we're the on-call.

## Decision

We run **Redis 7.4 (Alpine) as a single-task ECS Fargate service**,
discoverable via AWS Cloud Map private DNS at
`redis.internal.idp.local:6379`, and store its endpoint in SSM Parameter
Store at `/INTERNAL_DEVELOPER_PLATFORM/REDIS_ADDR` for the API to read at
boot.

Concrete shape:

- Module: `infra/modules/aws/redis_ecs/`. Single Fargate task definition,
  256 CPU / 512 MiB memory, `--maxmemory 384mb --maxmemory-policy
  allkeys-lru --appendonly no --save ""`. No persistence by design (see
  Consequences).
- `desired_count = 1`. Multiple Redis tasks behind one DNS name would
  round-robin requests across independent caches, defeating
  centralization. If we ever want HA, the answer is replication
  (Redis Sentinel / Cluster) or moving to a managed service, not running
  more standalone tasks.
- Security group locked to inbound from the API task SG only. Redis has
  no auth configured on the network — the SG *is* the auth boundary.
- Same ECS cluster as the API service. Reuses the existing networking,
  IAM patterns, and observability path (CloudWatch logs).
- API client uses `github.com/redis/go-redis/v9`. `Reserve` uses `SET NX
  EX`; `Complete` and `Release` use small Lua scripts to keep state
  transitions atomic.

## Consequences

**Positive:**

- **Centralized:** all API replicas share one cache, satisfying the
  primary requirement from ADR-0002.
- **Cheap to operate:** ~$10/month for the Fargate task. No managed-service
  premium.
- **Reuses existing infra patterns.** Same cluster, same IAM patterns, same
  log group conventions as the API service. Nothing new to learn for an
  on-caller already familiar with the platform.
- **Simple network model.** Cloud Map gives us a stable DNS name; SG-to-SG
  rules give us authn at the network layer. No password management, no TLS
  cert rotation.

**Negative:**

- **No persistence.** Fargate tasks have no durable disk and we explicitly
  disabled AOF/RDB. When the task is replaced (deploy, AZ failure, image
  refresh), all idempotency keys are lost. The 24h replay window resets
  to zero, and any retry that arrives during the gap will re-publish to
  SQS. Mitigated by SQS's at-least-once semantics requiring consumer-side
  dedup anyway, but it is a real regression vs. ElastiCache or
  EFS-backed Redis.
- **Single point of failure.** With `desired_count = 1`, an ECS reschedule
  is a ~30s outage during which `Reserve` returns 500. Per ADR-0002, the
  API fails closed during storage outages. This is acceptable for a study
  platform; for true production traffic it would not be.
- **No replication, no failover.** Redis Sentinel/Cluster would give us
  HA but adds significant operational surface (multiple tasks, quorum
  configuration, client-side discovery). At our scale we judged this not
  worth the complexity.
- **Diverges from the "managed AWS services" pattern** the rest of the
  platform follows. Future readers may reasonably ask "why isn't this
  ElastiCache?" — this ADR is the answer.

## Alternatives considered

- **AWS ElastiCache (Redis OSS engine).** The textbook answer for
  production. Managed, multi-AZ failover, persistent, automatic backups,
  patched without our involvement. Cost is roughly $11/month for
  `cache.t4g.micro` — *not* meaningfully more than the Fargate task.
  Rejected here because the user explicitly chose to run Redis as a
  separate ECS service for the prep exercise. **This is the alternative
  most likely to win on a re-evaluation.**
- **Redis sidecar in the API task definition.** Cheapest option:
  zero new tasks, intra-task localhost networking. Rejected outright: each
  ECS replica gets its own sidecar Redis, so the cache is per-replica and
  not centralized. That is exactly the failure mode ADR-0002 sets out to
  fix.
- **In-memory `sync.Map` inside the API process.** Useful only for tests.
  Same per-replica problem as the sidecar. Rejected.
- **DynamoDB with a TTL attribute and conditional `PutItem`.** Atomic
  reserve via condition expression, managed, multi-AZ, native TTL. Real
  contender. Rejected because Redis was the explicit pre-existing choice
  in `Nubank.md` and lets us demonstrate cache-aside patterns later;
  worth revisiting if we ever need cross-region replication or stronger
  durability guarantees.
- **Self-hosted Redis on EC2.** All the operational surface of running
  Redis ourselves (patching, replacement, monitoring) without the
  cluster-orchestration story Fargate gives us. Strictly worse than the
  Fargate option.

## When to revisit

- If duplicate-publish rate at the API partial-failure window or during
  Redis task replacements becomes material in production metrics, move
  to **ElastiCache**. The `IdempotencyStore` port abstraction means this
  is an adapter swap, not a contract change.
- If we ever need HA Redis for reasons beyond idempotency (rate limiting
  across replicas, session caching), revisit at the platform level rather
  than incrementally hardening this one task.
- If we add a second internal service that needs Redis, evaluate whether
  one shared Redis (this one) or per-service caches is the right pattern.
  Sharing avoids duplicated infra; isolating avoids one service's hot
  keys evicting another's.
