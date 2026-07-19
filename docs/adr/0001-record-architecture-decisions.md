# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-05-03
- **Deciders:** Rafael Costa

## Context

The Internal Developer Platform spans multiple services (API in Go,
Provisioner in Go), AWS infrastructure (ECS, SQS,
Cognito, API Gateway, WAF), and platform-level contracts that clients depend
on. Decisions made today — choice of messaging, idempotency strategy, storage
backends, deployment topology — will be invisible six months from now unless
we write them down somewhere durable.

Code shows *what* the system does. Git history shows *when* something
changed. Neither shows *why*. Without a record of why a choice was made and
what alternatives were rejected, every future change either re-litigates
the same debate or accidentally regresses on a constraint nobody remembered.

## Decision

We record significant architectural decisions as Architecture Decision
Records (ADRs) in `/docs/adr/`, following the lightweight Nygard format
documented in `template.md` of that directory.

Specifically:

- One decision per ADR. If a record needs more than one page, it likely wants
  to be split into separate "what" and "how" decisions.
- Numbered sequentially with four-digit prefixes (`0001`, `0002`, ...) and
  kebab-case titles.
- Stored at the repo root under `/docs/adr/` for **platform-level**
  decisions — anything that crosses service or component boundaries.
  Service-internal decisions may live under that service's directory once
  the first such decision arises.
- Committed in the same pull request as the code that implements the
  decision, so review of the change and review of the rationale happen
  together.
- Immutable once `Accepted`. Decisions that are overturned are marked
  `Superseded by ADR-NNNN` and a new ADR is written; the old one is not
  edited or deleted.

## Consequences

**Positive:**

- New contributors can read the decision log to understand *why* the system
  is shaped the way it is, not just *what* it does today.
- The "alternatives considered" section captures rejected options, which
  stops the same debate from cycling around indefinitely.
- Writing down a decision forces clarity on the trade-offs. If we can't
  articulate why we picked X, we probably haven't actually decided.
- Interview-ready artifact: the log directly demonstrates decision-making
  under constraints, which is the bar for senior/staff engineering roles.

**Negative:**

- Adds a small documentation tax to every non-trivial change. Mitigated by
  keeping ADRs short and not requiring one for routine work (refactors, bug
  fixes, dependency bumps).
- Risks decay: if ADRs aren't updated when superseded, the log becomes
  misleading. Mitigated by treating supersession as part of the change that
  invalidates the old decision, and by surfacing status prominently in the
  index.

## Alternatives considered

- **Document decisions in the README.** Rejected: the README is a
  living overview that gets edited continuously, while ADRs need to be
  dated, immutable records. Mixing the two erases history.
- **Use a wiki (Confluence, Notion, GitHub Wiki).** Rejected: drifts from
  the code, can't be reviewed alongside a PR, and tends to rot when the
  underlying repo is the source of truth.
- **No formal process — rely on commit messages and PR descriptions.**
  Rejected: works for small changes but loses the cross-cutting picture.
  A decision like "we use SQS over Kafka" doesn't belong to a single commit.
