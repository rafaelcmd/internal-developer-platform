# cost-manager

A Clojure service responsible for managing and tracking cloud infrastructure costs across any cloud provider (AWS, GCP, Azure, etc.).

## Context

This service is part of the internal developer platform monorepo. The platform works as follows:

1. A Golang API receives requests to create cloud resources and publishes messages to AWS SQS.
2. This Clojure service consumes those messages and manages the cost tracking for each cloud resource created.

The goal is to provide a provider-agnostic cost management layer, regardless of which cloud provider the resource belongs to.

## Project Structure

```
src/cost_manager/   - application source code
test/cost_manager/  - tests mirroring the src structure
resources/          - configuration files and EDN data
```

## Running the project

```bash
clojure -M -m cost-manager.core
```

## Running tests

```bash
clojure -M:test
```

## Dependencies

Managed via `deps.edn`. Key dependencies:

- `org.clojure/clojure 1.12.0`
- `lambdaisland/kaocha` — test runner
