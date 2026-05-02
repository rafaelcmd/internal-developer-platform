## 🎯 Objective

Prepare to demonstrate:

* Strong decision-making under real constraints
* Clear articulation of trade-offs
* Understanding of scale, reliability, and cost
* Ability to design production-grade distributed systems

---

# 📅 Week 1 — Core Distributed Systems Fundamentals

## 📚 Topics

* [ ] Latency vs Throughput
* [ ] SLA, SLO, SLI
* [ ] Availability (error budgets)
* [ ] Consistency (Strong vs Eventual)
* [ ] CAP / PACELC
* [ ] Backpressure
* [ ] Idempotency

---

## 🛠️ IDP Features

### Idempotency Layer

* [ ] Create middleware `idempotency_middleware.go`
* [ ] Extract header `X-Idempotency-Key`
* [ ] Validate key format (UUID)
* [ ] Create storage interface
* [ ] Implement in-memory store
* [ ] Implement Redis store (optional)
* [ ] Return cached response for duplicates
* [ ] Add TTL (24h)
* [ ] Handle partial processing

---

### Request ID Propagation

* [ ] Generate `X-Request-ID`
* [ ] Inject into request context
* [ ] Add to logs
* [ ] Add to SQS attributes
* [ ] Extract in Provisioner
* [ ] Extract in Cost Manager

---

### SQS Consumer

* [ ] Create polling loop
* [ ] Configure batch size
* [ ] Configure visibility timeout
* [ ] Deserialize payload
* [ ] Validate schema
* [ ] Call application service
* [ ] Handle retries safely
* [ ] Handle malformed messages
* [ ] Log correlation ID

---

## 🗣️ Interview Prep

* [ ] Explain idempotency in payments
* [ ] Explain SQS guarantees
* [ ] Explain duplicate handling

---

# 📅 Week 2 — Data Layer

## 📚 Topics

* [ ] B-Tree vs LSM
* [ ] Indexing
* [ ] Replication
* [ ] Sharding
* [ ] Hot partitions
* [ ] CQRS

---

## 🛠️ IDP Features

### Provisioner Persistence

* [ ] Add PostgreSQL
* [ ] Create repository interface
* [ ] Insert resource
* [ ] Insert EC2 instance
* [ ] Use transactions
* [ ] Handle retries
* [ ] Add migrations

---

### JSONB Strategy

* [ ] Store dynamic fields
* [ ] Create queries
* [ ] Benchmark
* [ ] Document trade-offs

---

### CQRS

* [ ] Create write model
* [ ] Create read model
* [ ] Implement projection
* [ ] Ensure idempotency

---

### Ledger

* [ ] Create append-only table
* [ ] Add transaction_id
* [ ] Add amount
* [ ] Add currency
* [ ] Add timestamp
* [ ] Enforce immutability
* [ ] Add deduplication
* [ ] Create audit query

---

### Indexing

* [ ] Identify queries
* [ ] Add indexes
* [ ] Measure performance
* [ ] Document impact

---

## 🗣️ Interview Prep

* [ ] Design ledger
* [ ] Explain sharding
* [ ] Explain CQRS

---

# 📅 Week 3 — Messaging

## 📚 Topics

* [ ] REST vs gRPC
* [ ] Event-driven
* [ ] Messaging
* [ ] DLQ
* [ ] Retries
* [ ] Circuit breaker

---

## 🛠️ IDP Features

### DLQ

* [ ] Add DLQ in Terraform
* [ ] Configure maxReceiveCount
* [ ] Configure retention
* [ ] Add alarm
* [ ] Simulate failure

---

### Retry

* [ ] Exponential backoff
* [ ] Add jitter
* [ ] Log retries
* [ ] Define limits

---

### Circuit Breaker

* [ ] Create module
* [ ] Track failures
* [ ] Closed state
* [ ] Open state
* [ ] Half-open
* [ ] Reset timeout

---

### Kafka

* [ ] Add producer
* [ ] Add consumer
* [ ] Config toggle
* [ ] Compare SQS

---

## 🗣️ Interview Prep

* [ ] Explain SQS vs Kafka
* [ ] Design async system
* [ ] Handle slow dependency

---

# 📅 Week 4 — Scalability

## 📚 Topics

* [ ] Load balancing
* [ ] Caching
* [ ] Rate limiting
* [ ] Autoscaling

---

## 🛠️ IDP Features

### Rate Limiting

* [ ] Token bucket
* [ ] Track per user
* [ ] Return 429
* [ ] Add metrics

---

### Distributed Limiter

* [ ] Redis-based limiter
* [ ] Compare with local

---

### Cache

* [ ] Cache-aside
* [ ] TTL
* [ ] Invalidation
* [ ] Measure hit rate

---

### HPA

* [ ] Create YAML
* [ ] Configure CPU
* [ ] Test scaling

---

### Load Testing

* [ ] Normal load
* [ ] Spike
* [ ] Stress
* [ ] Measure latency
* [ ] Measure throughput
* [ ] Document bottlenecks

---

## 🗣️ Interview Prep

* [ ] Explain scaling
* [ ] Handle spikes
* [ ] Explain caching

---

# 📅 Week 5 — Resilience

## 📚 Topics

* [ ] Timeouts
* [ ] Retries
* [ ] Circuit breaker
* [ ] Bulkheads
* [ ] Failover

---

## 🛠️ IDP Features

### Health Checks

* [ ] Shallow check
* [ ] Deep check
* [ ] Validate DB
* [ ] Validate SQS
* [ ] Return degraded

---

### Bulkheads

* [ ] Separate auth
* [ ] Separate provision
* [ ] Limit concurrency

---

### Shutdown

* [ ] Drain messages
* [ ] Stop requests
* [ ] Prevent data loss

---

### Chaos Testing

* [ ] Inject latency
* [ ] Simulate SQS failure
* [ ] Simulate DB failure
* [ ] Analyze behavior

---

### Timeouts

* [ ] Add to all external calls
* [ ] Document decisions

---

## 🗣️ Interview Prep

* [ ] Design resilient system
* [ ] Handle DB outage
* [ ] Explain isolation

---

# 📅 Week 6 — Full System Design

## 🧪 Designs

* [ ] Payment system
* [ ] Notification system
* [ ] Internal Developer Platform

---

## 🛠️ Final Tasks

### End-to-End

* [ ] API → SQS → Provisioner → DB → Cost Manager
* [ ] Validate flow

---

### ADRs

* [ ] Messaging decision
* [ ] CQRS decision
* [ ] Idempotency decision
* [ ] Rate limiting decision

---

### Observability

* [ ] Latency metrics
* [ ] Error rate
* [ ] Queue metrics
* [ ] Dashboards

---

# 📊 Progress Tracker

| Week | Theory | Features | Practice | Status |
| ---- | ------ | -------- | -------- | ------ |
| 1    | [ ]    | [ ]      | [ ]      | [ ]    |
| 2    | [ ]    | [ ]      | [ ]      | [ ]    |
| 3    | [ ]    | [ ]      | [ ]      | [ ]    |
| 4    | [ ]    | [ ]      | [ ]      | [ ]    |
| 5    | [ ]    | [ ]      | [ ]      | [ ]    |
| 6    | [ ]    | [ ]      | [ ]      | [ ]    |
