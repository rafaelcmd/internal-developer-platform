# Provisioner API Gateway — Edge stack (dev)

This is **stage 3 of 3** in the dev environment. It owns the public edge:
Cognito user pool, WAF web ACL, API Gateway REST API, and the VPC Link that
points API Gateway at the in-cluster API service.

This stack depends on an NLB that does **not** exist at the moment EKS is
created — the AWS Load Balancer Controller provisions it lazily from the
`k8s/api/service.yaml` manifest. That's why edge wiring lives in its own stack:
`data "aws_lb" "api"` would fail in a single combined apply.

## Deploy order

```
1. terraform apply (provisioner_api/dev)        → EKS, SQS, Datadog forwarder
2. kubectl apply -f k8s/redis/  k8s/api/        → LB controller creates the NLB
3. terraform apply (here)                       → wires API Gateway to the NLB
```

The NLB lookup matches by name (`var.nlb_name`), so it has to match the
`service.beta.kubernetes.io/aws-load-balancer-name` annotation on
`k8s/api/service.yaml`.

## Prereqs (before applying here)

```sh
# The NLB must already exist in AWS:
aws elbv2 describe-load-balancers --names idp-api-nlb --region us-east-1
```

If that returns "couldn't find resource", go back to stage 2 (`kubectl get svc`,
check the AWS Load Balancer Controller logs).

## Usage

```sh
cd infra/live/provisioner_api_gateway/dev
terraform init
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

## Layout
- Stack: `infra/live/provisioner_api_gateway/dev`, modules from `infra/modules/aws/*`.
- State: Terraform Cloud workspace `internal-developer-platform-provisioner-api-gateway-dev`.

## Files
- backend.tf: Terraform Cloud workspace configuration
- versions.tf: required Terraform and providers
- providers.tf: AWS provider only (no Kubernetes/Helm — this stack doesn't talk to the cluster)
- locals.tf: shared tags
- variables.tf: input schema
- dev.tfvars: environment values for dev
- main.tf: Cognito + WAF + API Gateway composition
- data.tf: NLB lookup by name
- outputs.tf: API Gateway, Cognito, and NLB outputs

## Teardown order

Reverse of apply: destroy this stack first (releases the VPC Link), then
`kubectl delete` the API service (releases the NLB), then destroy the platform
stack.
