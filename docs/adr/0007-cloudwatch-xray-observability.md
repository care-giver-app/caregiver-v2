# 0007 — CloudWatch + X-Ray Native Observability with Cost Guardrails

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

We need production logs, metrics, traces, and alerts. AWS-native is the cheapest and most transferable choice, but CloudWatch has been a surprise-bill source for Trevor in the past, so the choice needs explicit guardrails.

## Considered Options

- **CloudWatch + X-Ray native** — AWS-native, free tier covers our traffic if disciplined.
- **CloudWatch + managed APM (Datadog, Honeycomb)** — better UX, third-party cost.
- **Self-hosted (Grafana + Loki + Tempo)** — full control, ops burden.

## Decision

CloudWatch native + X-Ray with hard guardrails:

- ~8 custom metrics maximum (a new metric requires an ADR or a removal).
- No high-cardinality dimensions (user_id, raw paths, tenant_id raw).
- 2 dashboards max (prod + dev), defined in CDK.
- ≤8 prod alarms, ≤4 dev alarms.
- Log retention enforced in CDK: 7d dev, 30d prod.
- Billing alarm at $5/month CloudWatch, AWS Budgets at $20/month overall.

## Consequences

### Positive

- Cost is essentially $0 at our scale, with tripwires if that changes.
- Native to the rest of the stack; no extra egress or vendor dependency.

### Negative / Trade-offs

- CloudWatch UX is functional, not delightful.
- Discipline must be maintained as features grow.

## Related

- Spec: §11
