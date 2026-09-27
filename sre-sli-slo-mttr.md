# SRE — Confiabilidade e Golden Metrics
## donation-service (Hot Path / Caminho Crítico)

---

## 1. SLI/SLO Definitions

`donation-service` processes donation transactions and is the platform's
critical path: every donation that fails to register is a donor lost and
an NGO under-funded. Two SLIs, both grounded in the Golden Signals
(Latency and Errors), are defined below.

### SLI 1 — Latency

**Definition:** The proportion of HTTP requests to `donation-service`
that complete in under 300ms, measured at the server (`operation:
http.server.request`), captured via OpenTelemetry trace spans and
exported to Datadog APM.

**Measurement source:** `trace.http.server.request` (Datadog
APM-derived metric, `p50`/`p95`/`p99` percentile aggregations),
visualized on the `donation-service SRE Dashboard`.

**SLO:** 95% of requests complete in under 300ms, measured over a
rolling 30-day window.

**Rationale:** 300ms is a conservative threshold for a synchronous
POST that performs one database insert and dispatches one asynchronous
SQS message; the current measured p95/p99 in staging traffic sits in
the 100-150µs range (microseconds, not milliseconds), so this SLO
carries wide headroom by design — appropriate for a newly-launched
service still building a production traffic baseline.

### SLI 2 — Error Rate (Availability)

**Definition:** The proportion of HTTP requests to `donation-service`
that do **not** return a 5xx server error, measured at the server.

**Measurement source:** `trace.http.server.request.errors` /
`trace.http.server.request.hits` (Datadog APM-derived metrics),
computed as `(1 - errors/total) * 100`.

**SLO:** 99.5% success rate, measured over a rolling 30-day window.

**Error budget:** 99.5% success over 30 days permits approximately
**3 hours 36 minutes** of cumulative failed-request time per month
before the SLO is breached. This budget is the operational lever for
prioritization: as long as budget remains, feature work continues
normally; once it is exhausted, incident response and stability work
take priority over new deployments.

### Supporting signal — Apdex

**Definition:** Datadog's composite satisfaction score
(`trace.http.server.request.apdex`), blending latency tolerance and
error impact into a single 0–1 value.

Not one of the two required SLIs, but tracked on the same dashboard as
a fast, at-a-glance health signal for the pitch/demo.

---

## 2. SRE Dashboard

Implemented in Datadog (`donation-service SRE Dashboard`), covering:
- Request Rate (Hits)
- Error Rate (%)
- Latency Percentiles (p50/p95/p99)
- Errors by HTTP Status
- Apdex Score
- SLO: Success Rate (target 99.5%) — live value
- SLO: p95 Latency (target < 300ms) — live value

This satisfies the requirement for a dashboard focused exclusively on
SLOs and error-budget consumption for the platform's Hot Path service.

---

## 3. MTTR — How Observability Reduced Recovery Time

During infrastructure setup and initial deployment, five real incidents
were encountered, diagnosed, and resolved using the observability and
GitOps stack described above. Each is evidence of the stack actively
reducing Mean Time To Recovery, not merely reporting on failures after
the fact.

### Incident 1 — Database connectivity blocked (security group)

**Symptom:** `donation-service` and `ngo-service` pods entered
`CrashLoopBackOff` immediately after startup.
**Detection:** `kubectl logs` surfaced the exact failing operation —
`could not translate host name` (DNS), later `Connection timed out`
(network) — directly from application startup logs, with no need to
guess at the failure domain.
**Diagnosis:** A throwaway diagnostic pod (`psql` client) run inside
the same namespace isolated the fault to network reachability within
one command, distinguishing a security-group block from a credentials
problem before either was assumed.
**Resolution:** RDS security group ingress rule corrected to allow
traffic from the actual EKS node security group.
**Hardening:** The fix was subsequently moved into Terraform (rather
than left as a manual AWS CLI change), preventing the same incident
from recurring on the next infrastructure apply.

### Incident 2 — Stale/placeholder database credentials

**Symptom:** Connectivity succeeded but authentication failed
(`password authentication failed for user "postgres"`).
**Detection:** Application logs distinguished this precisely from
Incident 1 — a network-layer fix had already landed, and the next
layer of the stack failed cleanly and specifically, rather than
presenting as a repeat of the same symptom.
**Diagnosis:** Traced to `CHANGE_ME` placeholder values checked into
`terraform.tfvars` and applied as the literal RDS master password.
**Resolution:** Real generated passwords set via Terraform, propagated
through AWS Secrets Manager into Kubernetes Secrets.

### Incident 3 — Node pod-capacity exhaustion

**Symptom:** ArgoCD, application, and observability pods stuck
`Pending` cluster-wide.
**Detection:** `kubectl get events` immediately surfaced the specific
scheduler reason (`Too many pods`) rather than a generic resource
shortage, correctly ruling out a CPU/memory problem within seconds.
**Diagnosis:** Correlated to the AWS Free Tier's `t3.micro` instance
type, which limits pods-per-node via ENI/IP allocation math — not a
workload-sizing problem.
**Resolution:** Node instance type moved to `t3.small`, VPC CNI prefix
delegation enabled, and desired node count corrected in Terraform after
an initial fix (applied manually) was silently reverted by a
subsequent `terraform apply` — a recurrence directly caused by fixing
infrastructure state without updating the corresponding IaC source of
truth, resolved once identified.

### Incident 4 — Stale container image reference

**Symptom:** Application pods stuck in `ImagePullBackOff`.
**Detection:** `kubectl describe pod` reported the exact missing tag
against the exact registry path, eliminating ambiguity between "image
doesn't exist" and "wrong credentials" or "wrong region" immediately.
**Diagnosis:** The GitOps values file referenced a commit SHA that had
never been successfully pushed to ECR by CI.
**Resolution:** A fresh commit triggered a complete CI run, producing a
valid image and an automated GitOps pull request with the correct tag.

### Incident 5 — Observability stack silently failing to deploy

**Symptom:** ArgoCD reported Prometheus, Loki, and OTel Collector
Applications as healthy, but zero pods existed in the `monitoring`
namespace.
**Detection:** Cross-referencing the ArgoCD Application's live spec
against the Git source directly (`kubectl get application ... -o
jsonpath`) revealed the desired state itself was wrong, not merely
unsynced — a class of fault invisible from pod status alone.
**Diagnosis:** The Helm chart `repoURL` had been rewritten to point at
the GitOps repository instead of the actual public Helm chart
repository, causing every chart-fetch attempt to fail with `404 Not
Found`.
**Resolution:** `repoURL` corrected per component; ArgoCD Applications
deleted and recreated (rather than refreshed) to bypass stale
comparison-state caching that had masked the fix on first attempt.

### Summary

In every incident above, MTTR was governed by the same three-stage
loop: **structured logs/events pinpointed the failure domain in under a
minute; a targeted diagnostic step (a throwaway pod, a direct
`kubectl`/`aws` query, a live-state comparison) confirmed the specific
root cause before any fix was attempted; and the GitOps model made the
fix itself auditable and, in most cases, self-reverting if wrong.** No
incident required speculative trial-and-error against the running
system — each was root-caused from evidence the stack already
produced, which is the central claim of this section: **the
observability and GitOps investment directly and measurably shortens
recovery time**, rather than merely making failures visible after the
fact.
