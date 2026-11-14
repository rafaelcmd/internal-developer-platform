# ADR-0009: Pipeline roles manage IAM only by path, under a permissions boundary

- **Status:** Proposed
- **Date:** 2026-11-10
- **Deciders:** Platform team
- **Related:** `infra/live/shared/iam-github-oidc/`, `infra/modules/aws/irsa/`

## Context

Every Terraform component applies under its own role, `github-actions-tf-<component>`,
assumed from GitHub Actions through OIDC. Several of those components create IAM
roles: the IRSA roles of their pods, the Step Functions execution role, the EKS
cluster and Fargate roles, the API Gateway CloudWatch role and the Datadog
integration role.

The pipeline policies authorized that IAM work through the `Project` tag:
creating a role required `aws:RequestTag/Project`, changing one required
`aws:ResourceTag/Project`. Three properties of that model combined into a path to
full account administration for any workflow merged to `main`:

1. `iam:TagRole` was granted on `Resource "*"` with only the request-tag
   condition, so a pipeline could put `Project` on any role and then gain
   `AttachRolePolicy` and `UpdateAssumeRolePolicy` on it.
2. The pipeline roles carry `Project` themselves, so each could attach
   `AdministratorAccess` to its own role without retagging anything.
3. An unused role, `github-actions-oidc-role`, held `AdministratorAccess` and
   trusted `main`.

Trust was also broad: any workflow file on `main` could assume any component role
or the deploy role, and the repository was identified by its name, which can be
renamed or reclaimed.

Tags make a weak authorization boundary for IAM when the principal can write the
tags. IAM offers two stronger mechanisms that the principal cannot change: the
IAM path in a role's ARN, and a permissions boundary pinned through the
`iam:PermissionsBoundary` condition key.

## Decision

We authorize pipeline IAM work by path and boundary, and keep the tag model for
the other services.

**Workload roles.** Every role a pipeline creates for a workload lives under
`/idp/workload/<component>/` and carries the boundary
`internal-developer-platform-dev-workload-boundary` (path `/idp/boundary/`).
A component's pipeline may create, change and delete roles and managed policies
only under its own path. Every call that changes what a role may do
(`CreateRole`, `AttachRolePolicy`, `DetachRolePolicy`, `PutRolePolicy`,
`DeleteRolePolicy`, `PutRolePermissionsBoundary`) requires
`iam:PermissionsBoundary` to equal that boundary. The boundary allows the
services workloads call and explicitly denies IAM writes, `sts:AssumeRole`,
Organizations and Account. Component stacks read its ARN from
`/idp/shared/iam/workload_boundary_arn` (ADR-0007); the pipeline grants pin the
ARN itself, so a rewritten parameter can only make an apply fail.

**Service roles.** Three roles cannot move to a path without harm: EKS cannot
change a cluster's role in place, Fargate profiles cannot change their execution
role in place, and Datadog addresses its role by name. These are granted by exact
ARN:

- The EKS cluster role and the API Gateway CloudWatch role may hold only their
  one AWS-managed policy, pinned with `iam:PolicyARN`, and no inline policy.
- The Fargate pod execution role carries the workload boundary, because the api
  pipeline also owns the logging policy attached to it.
- The Datadog integration role's permissions are a managed policy owned by the
  bootstrap stack (`datadog_integration_policy.tf`). The datadog pipeline may
  attach it and `SecurityAudit`, and nothing else.

**Shared denies** in `policy_common.tf`, attached to every pipeline role:

- `sts:AssumeRole` is denied, so a role whose trust a pipeline rewrote still
  cannot be assumed by that pipeline.
- Everything except `iam:Get*`/`iam:List*` is denied on the pipeline roles, the
  GitHub OIDC provider, the pipeline policies, the boundary and the integration
  policy.
- Writes to `/idp/shared/iam/*` parameters, boundary removal, and attaching
  `AdministratorAccess`, `IAMFullAccess` or `PowerUserAccess` are denied.
- The `Project` tag cannot be removed from any resource, and EC2 `CreateTags`
  carrying `Project` is denied outside a create call (`ec2:CreateAction` absent).

**Trust.** Every pipeline role's trust policy pins `repository_id` and
`repository_owner_id`. Terraform roles also pin `job_workflow_ref` to
`_terraform.yml@refs/heads/main`, the deploy role to `cd-*.yml@refs/heads/main`
with the branch subject only, and the plan role to `_terraform.yml` on pull
requests.

**Removed.** `github-actions-oidc-role` and the Terraform Cloud role
(`terraform-cloud-oidc-role`) with its four policies. The Terraform Cloud OIDC
provider remains with no role trusting it.

## Consequences

- A pipeline can no longer reach account administration through IAM. The most a
  compromised pipeline can mint is a role within the workload boundary, or a
  service role holding its one AWS-managed policy.
- Each pipeline's IAM reach is its own component: the api pipeline cannot change
  the scaffolder's roles.
- Moving the workload roles to their paths replaces them. IAM role names are
  unique regardless of path, so each is destroyed before its replacement exists.
  Pods keep the old role ARN in their environment until restarted, so each
  Deployment needs a rollout restart after its stack applies.
- The first apply of each component after this change deletes roles at the root
  path, which the new grants no longer cover. That one apply runs with operator
  credentials; later applies run in the pipeline.
- A pipeline can still rewrite the trust policy of a role in its own path, which
  `UpdateAssumeRolePolicy` cannot be conditioned against. Such a role is capped
  by the boundary, and the pipeline itself cannot assume it. An organization
  guardrail on `aws:PrincipalOrgID` would close the remaining cross-account case.
- The Datadog baseline policy now changes through the bootstrap stack, applied by
  hand, rather than through the datadog pipeline.
- A new workload service needs its actions in the boundary before any role can
  use them; a missing action fails as an implicit deny naming the boundary.
- Tag scoping for other services remains: SQS, SNS, CloudWatch, Logs, Cognito,
  Secrets Manager and KMS tag calls still need only the request tag. Those reach
  resources, not IAM, so they do not lead to escalation; KMS keys have no
  name-based ARN to scope by.

## Alternatives considered

- **Keep the tag model and protect the tag.** An `aws:TagKeys` deny stops
  retagging, but the pipeline roles carry `Project` already, so self-modification
  remains. Tags also give no per-component separation without one tag value per
  pipeline.
- **Exact-name ARNs for every role.** Needs no role replacement, but every new
  workload role requires a change to the bootstrap stack, which is applied by
  hand. Paths let a component add roles freely within its own scope.
- **A permissions boundary on the EKS cluster and Datadog roles.** The boundary
  would have to mirror `AmazonEKSClusterPolicy` or Datadog's crawl policy action
  for action. Pinning the attachable policy gives the same ceiling with no copy
  to keep in sync.
- **Move the service roles to paths as well.** Replacing the cluster role
  replaces the cluster; replacing the Fargate role replaces every profile;
  Datadog would stop finding its role.
- **Split Terraform roles into separate plan and apply roles.** Would let the
  apply role trust only `environment:*` subjects. It needs `_terraform.yml` to
  select a role per job; `job_workflow_ref` already limits the roles to the one
  workflow, so the split is left for later.

## When to revisit

- When the account joins an AWS Organization: add SCPs and an RCP on
  `aws:PrincipalOrgID`, and consider whether the explicit denies here belong in an
  SCP instead.
- When a second environment is added: the path gains an environment segment, or
  each environment gets its own account.
- When a workload needs a service the boundary does not list.
