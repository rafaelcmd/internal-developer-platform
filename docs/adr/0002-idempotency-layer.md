# ADR-0002: API-edge idempotency layer

- **Status:** Accepted
- **Date:** 2026-05-03
- **Deciders:** Rafael Costa
- **Related:** ADR-0003 (Redis on ECS as the idempotency store)

## Context

`POST /v1/provision` accepts a resource provisioning request, publishes it
to SQS, and returns `202 Accepted`. The publish call is fire-and-forget
from the client's perspective: the API returns success the moment SQS
acknowledges the message.

Two real failure modes break this:

1. **Network retries from the client.** If the client doesn't see the 202
   (timeout, dropped connection, transient 5xx), it retries. The retry
   succeeds, and SQS now holds two copies of the same provisioning request.
   Downstream we provision two VMs.
2. **Client-side bugs.** A misconfigured caller (a CI job re-running, a UI
   double-click) submits the same logical action multiple times.

The API also runs as multiple ECS Fargate replicas behind a load balancer,
so any per-process deduplication (in-memory map) does nothing across
replicas — request 1 hits replica A, retry hits replica B, both succeed.

Constraints in play:

- Clients of this endpoint are internal (other services, CLI, future UI).
  We control the contract.
- The endpoint is async (`202 Accepted`); there is no strongly-consistent
  result the client can poll for at submission time.
- SQS provides at-least-once delivery, so even with perfect API-side
  deduplication, **consumers must independently dedupe.** This ADR does
  not solve that — it solves the *submission* duplication problem only.
- We're using Redis on ECS as the storage backend; see ADR-0003 for that
  choice.

## Decision

We add an idempotency middleware at the API edge that deduplicates
`POST /v1/provision` requests using a client-supplied UUIDv4 key.

Concrete shape:

- **Header:** `X-Idempotency-Key`. Optional in v1 (passed through if
  absent), validated as UUID when present. Made required at the route
  level later if we decide to enforce it.
- **Scope:** `POST /v1/provision` only. Health, swagger, and Cognito
  auth endpoints are explicitly out of scope. Auth has its own provider
  semantics (`UsernameExistsException`, etc.) that don't compose cleanly
  with naive response caching.
- **Body fingerprint:** the middleware computes `sha256(request body)` and
  stores it alongside the key. Reusing a key with a different body returns
  `422 IDEMPOTENCY_KEY_MISMATCH`. This protects against buggy clients
  poisoning a cached response.
- **State machine:** records move `IN_FLIGHT → COMPLETED`. A second
  request that arrives while the first is still running gets
  `409 IDEMPOTENT_REQUEST_IN_PROGRESS` with a short `Retry-After`. A
  second request that arrives after completion gets the cached response
  replayed verbatim, with `X-Idempotent-Replay: true` set on the response.
- **TTL:** 24 hours. Long enough to cover client retry loops and CI
  reruns; short enough that key collisions in UUIDv4 (already astronomically
  unlikely) become irrelevant.
- **5xx are not cached.** If the handler returns ≥500, the reservation is
  released so a retry can succeed. Caching transient backend errors for 24h
  would be a regression.
- **Storage:** abstracted behind an `IdempotencyStore` outbound port
  (`Reserve` / `Complete` / `Release`). The Redis implementation is one
  adapter; choosing it is ADR-0003's concern.

Key generation responsibility:

- Clients generate the UUIDv4 *once per logical action*, before the first
  attempt, and reuse it on retries. The key is opaque to the server.
- We do **not** auto-generate a key when the header is missing — that
  would look helpful but provides zero idempotency benefit, since a
  retrying client without the header would just get a fresh key each time.

## Consequences

**Positive:**

- Stops duplicate SQS publishes from client-side retries within the
  24h window.
- Single port abstraction means we can swap storage backends (in-memory
  for tests, Redis for prod, future ElastiCache) without touching the
  middleware or handlers.
- Body-hash mismatch detection (422) catches client bugs early instead of
  letting them poison the cache.
- The replay header makes idempotent behavior visible to clients and to
  observability — useful both for debugging and for measuring how often
  retries actually deduplicate.

**Negative:**

- **Does not make the system end-to-end idempotent.** SQS is at-least-once.
  The Cost Manager and Provisioner consumers will each receive duplicates
  of legitimately-distinct messages and must dedupe independently (DB
  unique constraint on `(idempotency_key, payload_hash)`). That work is
  out of scope here and will be its own ADR when implemented.
- Hard dependency on the storage backend for mutating endpoints. If Redis
  is unreachable, `Reserve` fails and the request returns 500. We chose
  fail-closed (correctness over availability) because silently disabling
  idempotency on errors would defeat the purpose. ADR-0003 covers the
  reliability characteristics of the backend.
- **Partial-publish window.** If the handler reserves the key, publishes
  to SQS successfully, then crashes before `Complete`, the message is on
  the queue but the reservation will eventually be released or expire —
  a retry would re-publish. The clean fix is a transactional outbox; for
  now we accept the rare double-publish and rely on consumer-side dedup
  (which we need anyway for SQS semantics).
- Adds a 24h key-namespace per client. Clients that aggressively reuse
  the same key for *different* intents will get 422s. This is desired
  behavior, but worth documenting in the API contract.

## Alternatives considered

- **Required header from day one.** Rejected for v1: forces every existing
  caller to change at once. Optional with a config switch lets us roll out
  enforcement gradually once observability shows the major callers are
  sending keys.
- **Reuse `X-Request-Id` as the idempotency key.** Rejected: tracing and
  deduplication are different concerns. API Gateway already overwrites
  `X-Request-Id` with `$context.requestId` (see `swagger.yaml:324`), so the
  client's tracing ID never reaches the API anyway. Keeping
  `X-Idempotency-Key` separate avoids accidental coupling.
- **Server-generated key when header is absent.** Rejected: provides no
  retry-deduplication benefit, since a retrying client without the header
  would generate a fresh ID each call. Looks helpful, isn't.
- **Hash the request body and use the hash as the key.** Rejected: tiny
  changes to JSON formatting (whitespace, field reordering by a buggy
  serializer) would produce different keys for what the client considers
  the same intent, defeating retry semantics.
- **Transactional outbox.** Rejected for now: solves the partial-publish
  window cleanly, but requires a database (the API has none today) and
  a separate publisher. Disproportionate scope for v1; revisit if the
  partial-publish window becomes a real problem in production data.
- **In-memory store per replica.** Rejected: doesn't dedupe across
  replicas, which is the failure mode we set out to fix. Useful only for
  tests.

## When to revisit

- If we build a UI client and need browser-driven idempotency; the optional
  header may need to become required for that surface.
- If consumer-side dedup goes in (Cost Manager / Provisioner), we should
  document the end-to-end contract in a follow-up ADR rather than leaving
  it scattered.
- If duplicate publishes at the partial-failure window prove material in
  prod metrics, escalate to an outbox pattern.
