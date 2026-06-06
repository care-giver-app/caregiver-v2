# 0009 — Go Backend, Next.js + React Web, SwiftUI iOS

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Trevor Williams

## Context and Problem Statement

We need a backend language, web framework, and iOS framework for the v2 build. Choices weight cold-start performance (Lambda), solo-dev velocity, and transferable skills for Trevor's day job.

## Considered Options

- **A.** Stay with v1 stack: Go + Angular + SwiftUI.
- **B.** Modernize web only: Go + React/SvelteKit + SwiftUI.
- **C.** Full-stack TypeScript: Node + Next + SwiftUI.
- **D.** Go + SvelteKit + SwiftUI.

## Decision

Go for the backend (small Lambda binaries, fast cold start, existing skill), Next.js with React for the web (App Router, marketable React skill, AWS-friendly), SwiftUI for iOS (modern declarative, iOS 17+ minimum target).

## Consequences

### Positive

- Cold-start friendly Lambda (Go binaries are tiny on `provided.al2023`).
- React skill transferable to Trevor's day job.
- One frontend framework convention across web and iOS (declarative UI).

### Negative / Trade-offs

- Three languages to maintain in one repo.
- Cross-language test infra is more complex than full-stack TS would be.

## Related

- Spec: §13
