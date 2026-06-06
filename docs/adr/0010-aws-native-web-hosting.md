# 0010 — AWS-Native Web Hosting (CloudFront + S3 + Lambda for SSR)

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

Next.js can be hosted on Vercel (smooth DX) or AWS (more setup, single cloud, single bill). The "minimize cost" and "AWS-native" goals point one direction; the "fastest DX" goal points the other.

## Considered Options

- **Vercel** — best Next.js DX, external dependency.
- **Cloudflare Pages** — fast, external dependency.
- **AWS-native (CloudFront + S3 + Lambda for SSR)** — single cloud, single bill, more setup.

## Decision

AWS-native. Static assets in S3, served via CloudFront. SSR via Lambda (Function URL) or Lambda@Edge depending on which Next.js adapter we land on at C2 time.

## Consequences

### Positive

- Single AWS bill; cost stays bounded with our existing guardrails.
- IAM and Cognito integrations are natural.
- Skill applies to many AWS shops.

### Negative / Trade-offs

- Next.js + Lambda SSR is more setup than Vercel's drop-in deploy.
- The `@aws-sdk` / Next.js integration still has rough edges (will revisit at C2).

## Related

- Spec: §13
