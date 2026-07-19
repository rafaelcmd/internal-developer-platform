# OpenTelemetry Collector

The vendor-agnostic telemetry seam. Every service ships OTLP here; this Collector
decides which backend(s) telemetry lands in (Datadog today), so swapping or adding
a backend is a Collector config change — not an application redeploy.

## Ownership split

Because it runs on EKS Fargate and uses IRSA, the pieces are split between
Terraform (`infra/modules/aws/eks/otel_collector.tf`) and raw manifests here:

| Object | Owned by | Why |
|---|---|---|
| `observability` namespace | Terraform | Also auto-added to the Fargate profile |
| ServiceAccount `otel-collector` | Terraform | IRSA annotation needs the IAM role ARN (a TF output) |
| Secret `datadog-api-key` | Terraform | Same key material as the rest of the stack |
| IAM role (IRSA) | Terraform | For AMP `aps:RemoteWrite` once AMP is added |
| ConfigMap / Deployment / Service | manifests here | The workload |
| ClusterRole + binding (`rbac.yaml`) | manifests here | Read-only K8s metadata access |

## Deploy order

1. `terraform apply` with `install_otel_collector = true` (creates namespace,
   ServiceAccount, secret, IRSA role).
2. `kubectl apply -f k8s/otel-collector/` (ConfigMap, RBAC, Deployment, Service).

## Endpoints

Services target `OTEL_EXPORTER_OTLP_ENDPOINT`:

- `http://otel-collector.observability.svc.cluster.local:4318` (OTLP/HTTP)
- `otel-collector.observability.svc.cluster.local:4317` (OTLP/gRPC)

## Notes

- **Single replica is intentional.** The `prometheus` receiver scrapes targets;
  more replicas would double-scrape. For HA, split into a 1-replica scraper + an
  N-replica OTLP gateway (or use the OTel Operator target allocator).
- **No IMDS on Fargate**, so resource detection uses the `env` detector +
  `k8sattributes`, not the `ec2`/`eks` cloud detectors.
