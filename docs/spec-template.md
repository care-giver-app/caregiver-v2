# <Feature Name>

- **Module:** ios | api | infra | shared/go-common
- **Status:** Current
- **Last updated:** YYYY-MM-DD
- **Contract:** <OpenAPI operations / types this feature touches, or "none">
- **Related specs:** [[other-spec-name]], ADR(s)

> **About this spec.** This is a **living, conceptual** spec for **one module**. It describes _what
> this feature does and why_ — not how a single change was implemented. Edit it in place as the
> feature evolves; it should always reflect the current intended state. Specs do **not** describe
> other modules: the interface between modules is owned by the OpenAPI contract
> (`shared/openapi/openapi.yaml`), which this spec references but never duplicates.
>
> Implementation **plans are disposable and gitignored** — generated from this spec when it's time to
> write code, then thrown away. The spec is the source of truth; the plan is scaffolding.

## Purpose

One or two sentences: what this feature is and who it serves.

## Behavior

Plain-language description of what the feature does — the conceptual big picture. Read this to
understand the feature without reading code.

- For **ios** specs: the screen / flow, its states, navigation.
- For **api** specs: endpoint behavior, validation, authorization rules.
- For **infra** specs: the resources, their relationships, wiring.

## Key decisions

The decisions that shape this feature — the running record of _why it is the way it is_. Append here
as the feature evolves (this section doubles as the feature's history).

| Decision | Choice | Why |
| -------- | ------ | --- |
|          |        |     |

## Where it lives

Map from concept → code, scoped to **this module only**. This is the bridge that lets you (or
future-you) open the right file and contribute by hand without re-deriving the layout.

| Concept | File |
| ------- | ---- |
|         |      |

## Non-goals

What this feature deliberately does **not** do, and what's intentionally deferred.
