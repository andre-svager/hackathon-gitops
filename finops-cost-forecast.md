# FinOps — Cost Forecast & Optimization
## SolidaryTech Production Environment (us-east-1)

All rates below are AWS on-demand list prices for `us-east-1`, current
as of 2026. Sources are AWS's public pricing pages and pricing
aggregators citing AWS's price list API; verify against AWS Cost
Explorer / Pricing Calculator before final budget sign-off, as rates
change over time.

---

## 1. Monthly Cost Forecast — Current Architecture

| Component | Qty | Unit Rate | Monthly Cost |
|---|---|---|---|
| EKS control plane (standard support) | 1 | $0.10/hr | $73.00 |
| EC2 `t3.small` worker nodes | 3 | $0.0208/hr | $45.53 |
| RDS `db.t3.micro` PostgreSQL, Single-AZ | 2 (ngo_db, donation_db) | ~$0.018/hr | $26.28 |
| RDS storage (gp3, 20GB assumed) | 2 | $0.115/GB-mo | $4.60 |
| NAT Gateway | 1 | $0.045/hr | $32.85 |
| NAT Gateway data processing (est. 20GB/mo) | — | $0.045/GB | $0.90 |
| Network Load Balancer (donation-service) | 1 | ~$0.0225/hr + LCU | ~$16.43 |
| DynamoDB (volunteer-service), on-demand | — | pay-per-request | ~$1–5 (low volume) |
| SQS (donation notifications) | — | pay-per-request | <$1 (low volume) |
| ECR storage | 3 repos | $0.10/GB-mo | ~$1.00 |
| Public IPv4 addresses (NAT GW, NLB) | 2 | $0.005/hr | $7.30 |
| **Estimated Total** | | | **~$209–213/month** |

**Notes:**
- Multi-AZ is intentionally disabled on both RDS instances (per existing
  Terraform comment: "Disabled for free tier compatibility") — this
  halves database cost but removes automatic failover; see the DR
  section of this report for how that risk is otherwise mitigated.
- This forecast excludes Datadog (external SaaS billing, outside AWS
  spend) and one-time/data-transfer-out charges, which vary by traffic
  volume and aren't yet measurable at this project's current stage.

---

## 2. Savings From Rightsizing (Section 2 of this plan)

Based on measured Prometheus/`kubectl top` data, `donation-service`
requests were reduced from `100m CPU / 128Mi memory` to `25m CPU / 48Mi
memory` (75% CPU, 62% memory reduction in reserved-but-unused
capacity). While Kubernetes `requests` don't directly bill (you pay
for the underlying EC2 node regardless), accurate rightsizing is what
allows the **node count/instance size itself to shrink safely** —
over-requested pods artificially inflate how many nodes the cluster
needs to satisfy scheduling, even when actual usage is low. Rightsizing
all three services is the precondition for any future node-count
reduction; it does not itself remove line items above, but it removes
the main blocker to doing so later.

---

## 3. Optimization Recommendation — NAT Gateway → VPC Interface Endpoints

**The single largest avoidable line item is the NAT Gateway**
(~$33.75/month base + processing), which exists almost entirely to let
private-subnet pods reach two AWS services: **ECR** (image pulls) and
**Secrets Manager / SSM** (credential retrieval). Neither of these
needs general internet access — they're AWS-internal API calls that
never need to leave AWS's network at all.

**Recommendation:** Replace the NAT Gateway with **VPC Interface
Endpoints (AWS PrivateLink)** for `com.amazonaws.us-east-1.ecr.api`,
`com.amazonaws.us-east-1.ecr.dkr`, `com.amazonaws.us-east-1.s3`
(gateway endpoint, no hourly charge), `secretsmanager`, and `ssm`.

**Cost comparison:**
| Approach | Monthly cost |
|---|---|
| NAT Gateway (current) | ~$33.75 base + $0.045/GB processed |
| 5 Interface Endpoints | ~$0.01/hr × 5 × 730hrs = ~$36.50 base + $0.01/GB |

At this project's current, low traffic volume, the direct hourly cost
is comparable — **the real saving is on the per-GB data-processing
rate**, which drops from $0.045/GB to $0.01/GB (78% cheaper per byte),
and this compounds as traffic grows. For a hackathon-scale
demonstration this is a **native AWS cost-optimization pattern** worth
citing in the report even if the immediate dollar delta is modest;
for a production-scale version of this platform processing real
donation traffic, it is the difference between a NAT bill that scales
linearly with usage and one that doesn't.

**Secondary recommendation (larger, longer-term saving):** once traffic
patterns are established, purchase a **1-year Compute Savings Plan**
covering the EC2 node fleet — ~38% off `t3.small` on-demand pricing
with no upfront payment required, since these are long-running,
predictable nodes (not bursty/ephemeral workloads where On-Demand or
Spot make more sense).

---

## Sources

- AWS EKS Pricing, 2026 — control plane $0.10/hr, us-east-1
- AWS EC2 t3.small on-demand pricing, us-east-1, 2026: $0.0208/hr
- AWS RDS db.t3.micro PostgreSQL, Single-AZ, us-east-1, 2026: ~$0.018/hr
- AWS NAT Gateway pricing, us-east-1, 2026: $0.045/hr + $0.045/GB
- AWS PrivateLink Interface Endpoint pricing, us-east-1: ~$0.01/hr/AZ + $0.01/GB
- AWS Application/Network Load Balancer pricing, us-east-1: ~$0.0225/hr + LCU
