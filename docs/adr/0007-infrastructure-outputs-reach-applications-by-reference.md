# ADR-0007: Scaffolded applications resolve infrastructure by reference

- **Status:** Proposed
- **Date:** 2026-09-20
- **Deciders:** Rafael Costa
- **Related:** ADR-0006 (Step Functions orchestrates provisioning), ADR-0005
  (Secrets Manager is reached through a VPC interface endpoint)

## Context

A provision request carries an application and the cloud resources it needs, and
the platform provisions both. The scaffolded application then has to be able to
reach what was created: an SQS consumer needs its queue, a service with a
datastore needs its database.

The obvious mechanism is to write the values into the repository. After the
infra worker finishes, `InjectInfraOutputs` rewrites `appsettings.json` with the
queue URL, the connection string, the table name. It is what a developer doing
this by hand would do, and it is what the step's name suggests.

Four forces push against it.

**Some of those values are credentials.** A database connection string carries a
username and a password. Writing one into a repository commits a credential to
git, and the identity performing the commit is the GitHub App, the one principal
in this platform with write access across the organisation. ADR-0005 moved a
single secret read off the public network to protect that App's own key;
committing database credentials with it would give back considerably more than
that gained.

**One repository is deployed to more than one environment.** A value injected at
scaffold time is a dev value. The same repository has to run in staging and
production, so an injected literal is wrong in every environment but the one it
was generated for, and a scaffolder that injects per-environment values has to
render per-environment repositories.

**An injected value is a point-in-time copy.** Terraform is the desired-state
control plane for every AWS resource in the platform. A queue recreated with a
new URL, a database failed over to a new endpoint, a resource renamed: each
leaves the repository holding a value that is now wrong, that nothing will
correct, and that no Terraform plan will report as drift, because git is not in
Terraform's state.

**It collapses the fork in the state machine.** If the rendered template depends
on the infra outputs, then `CreateRepository` and `ProvisionInfra` stop being
usefully concurrent: the repository a developer can actually clone and run
arrives only after the Terraform run. ADR-0006 keeps them parallel precisely to
avoid that, and value injection quietly takes it back.

The counter-force is real and is the reason the platform exists: the application
has to find the resource somehow, and "configure it yourself" is the toil an
internal developer platform is supposed to remove.

## Decision

Scaffolded applications resolve provisioned infrastructure **by reference at
runtime**, through a naming convention the platform owns, rather than by values
written into the repository.

The convention extends the one the platform already uses for its own services
(`/idp/<service>/<environment>/<name>`) to the applications it provisions:

```
/idp/<application>/<environment>/<resource>/<output>

/idp/payments-api/dev/orders/queue_url
/idp/payments-api/dev/orders/queue_name
/idp/payments-api/dev/ledger/endpoint
/idp/payments-api/dev/ledger/credentials_secret_arn
```

`<application>` and `<resource>` come from the provision request itself
(`Application.Name` and `Resource.Name`), so **the path is computable before
Terraform has provisioned anything**. That is the property the whole decision
rests on: the template renders against a contract, not against a result.

Three obligations follow.

**The infra worker publishes.** Every resource it provisions writes its outputs
to the agreed paths as part of provisioning, not as a later step. A resource
whose outputs are not published is not finished.

**The template renders the path, not the value.** `appsettings.json` carries
`/idp/{app}/{env}/orders/queue_url`, resolved at startup. This is the same thing
the scaffolder already does for itself: it takes a queue *name* and calls
`GetQueueUrl`, so no account id reaches a committed manifest. Golden-path
templates ship that resolution wired up, so an application author never writes
it.

**Credentials never travel as values.** A parameter holds a Secrets Manager ARN;
the secret holds the credential; the application's IRSA role is what authorises
reading it. Both SSM and Secrets Manager already have VPC interface endpoints,
so neither lookup leaves the VPC.

`InjectInfraOutputs` stays in the state machine and changes job. It is no longer
"rewrite the application's config with Terraform outputs"; it is a **verification
join**: every parameter the rendered template expects exists and is readable
before the request is reported successful. A missing parameter becomes a
provisioning failure with a name, rather than a `CrashLoopBackOff` the developer
debugs on their first morning.

The residue is values that genuinely cannot be a convention: an AWS-generated
name with a random suffix, an ARN carrying an account id, anything the requester
did not name. Where one of those must land in the repository, it lands as a
**pull request against the new repository after the fact**, not as a
pre-first-commit mutation. The developer still gets their repository
immediately, and the change arrives through review like any other change to
their code.

## Consequences

**Easier.** The repository is environment-agnostic, so promoting it from dev to
production is a deployment rather than a re-scaffold. Infrastructure can be
replaced underneath a running application without the repository going stale.
The fork in ADR-0006 stays genuinely concurrent, because the repository branch
no longer waits on the infra branch for anything a developer can see. No
credential is ever a candidate for a commit, which removes a class of incident
rather than mitigating it.

**Harder.** The platform now owns a naming convention, and a convention is a
contract with every repository ever scaffolded. Renaming a path is a breaking
change across applications the platform no longer controls, and there is no
compiler to catch it: the failure is at startup, in the application, which is
the worst place for it. The verification join exists to move that failure
forward to provision time, and it only works if it is kept honest as templates
change.

**Given up.** Legibility, mostly. `"QueueUrl": "/idp/payments-api/{env}/orders/queue_url"`
is a worse thing to read than a URL, and a developer debugging locally has to
know how the indirection resolves. Templates carry that explanation, and it is a
real cost paid on every repository to remove a risk that materialises on few of
them.

**New runtime dependency.** Every scaffolded application now depends on SSM
Parameter Store at startup. That is an availability dependency in the
application's own critical path, not the platform's, and it is the reason the
convention resolves at startup and caches rather than reading per request.

## Alternatives considered

- **Inject values into `appsettings.json` at scaffold time.** The intuitive
  option, and the one the step's name implies. Rejected on all four forces
  above, of which the credential one is not a trade-off: a connection string in
  a repository is a leaked credential regardless of what the rest of the design
  gets right.

- **Inject non-secret values, reference secrets only.** The apparent middle
  ground: queue URLs are not sensitive, so commit those and keep passwords in
  Secrets Manager. Rejected because it fixes the one force that has a hard
  boundary and leaves the other three untouched. A queue URL is still
  environment-specific and still goes stale when the queue is replaced. It also
  makes the rule a per-field judgement ("is this one sensitive?") applied by
  whoever writes the next template, which is a rule that decays.

- **Environment variables in `k8s/deployment.yaml`, populated from Terraform.**
  Moves the injection from the application's config to its manifest. Rejected:
  the manifest is in the same repository and inherits the same staleness and
  multi-environment problems, and it additionally makes per-application
  infrastructure knowledge a concern of the CD pipeline.

- **A platform service-discovery or catalog API the application calls at
  startup.** The answer at large scale, and where this convention eventually
  leads. Rejected now: it is a new service with its own availability, deployment
  and client library, introduced to solve a problem that Parameter Store already
  solves with an AWS SLA, an existing VPC interface endpoint, and IAM as its
  authorisation model.

- **`terraform_remote_state` from the application's own Terraform stub.** The
  application's stack reads the infra worker's state directly. Rejected: the
  platform's stacks decouple through SSM specifically so no workspace needs
  access to another's state file, and extending state access to every scaffolded
  application would invert that.

## When to revisit

- The number of parameters per application grows enough that a startup read is
  paging through `GetParametersByPath`. The convention has probably grown a level
  it does not need, or the resource wants one JSON-valued parameter instead of
  several flat ones.
- An output cannot be expressed as a flat path (a list of subnet ids is the
  likely first case). Try a JSON-valued parameter before concluding the
  convention is wrong.
- The residue that has to arrive as a follow-up pull request stops being a
  residue. If most requests produce one, the convention is not covering what it
  claims to cover.
- Parameter Store's availability becomes an application-level incident rather
  than a theoretical dependency, which is the signal that the catalog API above
  is worth its cost.
