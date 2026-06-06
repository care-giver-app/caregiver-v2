# 0008 — AWS CDK in TypeScript for IaC

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

V1 uses SAM (YAML). For v2 we want IaC that scales with the stack as services are added, gives us type safety, and builds a more transferable skill than SAM.

## Considered Options

- **SAM** — AWS native, YAML, serverless-focused, what we know.
- **AWS CDK (TypeScript)** — programmatic IaC, type-safe, AWS-native.
- **Terraform** — cloud-agnostic, larger community, HCL.
- **SST** — opinionated framework on CDK.

## Decision

AWS CDK in TypeScript. One CDK app with multiple stacks per environment. Stack split: `shared-stack` (tables, queues, AppConfig), then one stack per service.

## Consequences

### Positive

- Real abstractions (Constructs) for reusable infra patterns.
- IDE autocomplete + type-checking on infra changes.
- Native AWS, first-party support.
- `cdk diff` shows clear infra deltas on every PR.

### Negative / Trade-offs

- Steeper learning curve than SAM YAML.
- CDK version upgrades occasionally require code changes.
- CDK output is CloudFormation; some edge cases hit CFN limits.

## Related

- Spec: §12
