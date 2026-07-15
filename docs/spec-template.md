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

Write what the feature does as **EARS statements** — one testable requirement per line, so each rule
maps almost directly to a test. EARS (Easy Approach to Requirements Syntax) has five patterns; pick
the one that fits each rule, and name the actor concretely (the API, the screen, the stack) rather
than a generic "system":

- **Ubiquitous** (always true): _The `<actor>` shall `<response>`._
- **Event-driven** (`When`): _When `<trigger>`, the `<actor>` shall `<response>`._
- **State-driven** (`While`): _While `<state>`, the `<actor>` shall `<response>`._
- **Optional** (`Where`): _Where `<feature/param is present>`, the `<actor>` shall `<response>`._
- **Unwanted** (`If`/`Then`): _If `<unwanted condition>`, then the `<actor>` shall `<response>`._

Combine them for complex rules (e.g. _When X, if Y, then the API shall Z_). A short lead-in sentence
for the conceptual big picture is fine before the statements.

- For **api** / **infra** specs: EARS fits directly (endpoint behavior, validation, authorization,
  resource wiring) — prefer it.
- For **ios** specs: use EARS where it clarifies state/event rules; plain prose is fine for screen
  layout, navigation, and visual states where EARS reads awkwardly.

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
