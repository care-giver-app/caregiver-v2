# 0011 — v1/v2 Coexistence in Shared AWS Account

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

Caregiver v1 (SAM-deployed) and v2 (CDK-deployed) share AWS account 658340567265 in us-east-2 until v1 is retired. v2's GitHub Actions deploy role (`CaregiverGitHubDeploy`) has `AdministratorAccess`, meaning a misconfigured CDK app or a typo in a stack name could in theory overwrite v1 stacks or resources. We need a cheap, durable guardrail.

## Considered Options

- **Synth-time stack-name validation in CDK app** — fail `cdk synth` if any stack name doesn't match `^Caregiver(Dev|Prod)-`. Catches typos before any AWS call.
- **Tighten the IAM trust/permission policy** — scope `CaregiverGitHubDeploy` to only resources tagged `Project: Caregiver-v2`. Stronger but requires retrofitting tags onto every resource and writing a non-trivial IAM policy. Deferred.
- **Separate AWS accounts** — the textbook isolation. Requires AWS Organizations setup; flagged in spec §16 as a future ADR.

## Decision

Add a synth-time validation in `infra/bin/app.ts` that walks all stacks in the CDK app and throws if any stack name does not match `^Caregiver(Dev|Prod)-`. This runs locally on `cdk synth`, in CI on every PR, and again on prod deploys — so a bad stack name fails fast in three places before it can touch AWS.

Also document a constraint for the future B1 spec: v2 DynamoDB tables MUST be prefixed (e.g., `caregiver-v2-<entity>` or `caregiver-{stage}-<entity>`) so they don't collide with v1's unprefixed tables (`event-table-prod`, `user-table-prod`, etc.).

## Consequences

### Positive

- Cheap (~15 lines of code) and effective at preventing the most likely accident.
- Local `cdk synth` catches bad names before push.
- Naming convention is now enforced, not just documented.
- ADR carries forward the constraint to B1 design.

### Negative / Trade-offs

- Adds a small TypeScript check to the CDK app.
- If we ever want a stack named outside the `Caregiver(Dev|Prod)-` pattern (unlikely), we'd need to update the regex.
- Does NOT prevent intentional misuse of the admin role — that requires least-privilege IAM (a future ADR).

## Related

- Spec: `docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md` §16 (open question on dual-account topology)
- ADR-0008 (CDK as IaC)
- v1 stack inventory captured in PR description.
