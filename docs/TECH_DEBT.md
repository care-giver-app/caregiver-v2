# Tech debt & deferred follow-ups

Known, deliberately-deferred items. Each was evaluated and judged safe to defer at current
(single-family) scale. Revisit before opening the product to more tenants or when the noted trigger
applies.

## From the B1 code review (2026-06-11)

These surfaced in the B1 review; the security/correctness-critical findings were fixed in the B1 PR.
The following were deferred (family-scale-safe today):

- **`BatchGet` ignores `UnprocessedKeys` + the 100-key limit** — `shared/go-common/store/caregroup.go`
  (`CareGroupStore.BatchGet`). Used by `GET /me` and `GET /invitations/mine`. Under DynamoDB
  throttling or >100 ids, dropped keys silently become empty group names. _Fix:_ batch in ≤100-key
  chunks and retry `UnprocessedKeys`. _Trigger:_ users belonging to many groups, or throttling.
- **`queryPending` has no pagination** — `shared/go-common/store/invitation.go`
  (`ListPendingByEmail`/`ListPendingByGroup`). `status='pending'` is a post-read `FilterExpression`,
  so pending invites past the first 1 MB Query page are missed (affects the duplicate-pending guard
  and `GET /invitations/mine`). _Fix:_ paginate on `LastEvaluatedKey`. _Trigger:_ an email/group
  accumulating many accepted/revoked invitation rows.
- **Duplicate-pending invite is a GSI TOCTOU race** — `api/internal/handlers/caregroups.go`
  (`CreateInvitation`). Concurrent requests can both pass the check-then-create against the
  eventually-consistent `email-index`. Largely defused by the membership-overwrite guard already
  shipped (a duplicate pending invite is low-harm now). _Fix:_ deterministic invite key or a
  conditional write keyed on `(email, care_group_id)`.
- **Authed-route list is duplicated** — `infra/lib/api-stack.ts` (`authedRoutes`) and
  `api/cmd/lambda/mux.go` (`authn.Wrap` registrations) list the same routes with nothing keeping them
  in sync. _Fix:_ route sensitive handlers through one wrapped sub-mux and assert parity, or generate
  one list from the other.
- **Copy-pasted store get/query blocks (partially paid down in B3a)** — B3a added generic
  `getItem[T]`/`queryItems[T]` + a cursor codec in `shared/go-common/store/store.go`, and the new
  receiver/tracker/event stores consume them. The **four B1 stores** (user, care-group, membership,
  invitation) were **not** retrofitted onto the helpers and still hand-roll `GetItem`/`Query`. _Fix:_
  migrate them to the generics (and apply the missing-pagination fix above in the same pass).

## Contract / platform notes

- **Clients must send the Cognito _ID token_, not the access token.** The auth middleware reads
  `email` and `name` from the JWT claims (needed for invite matching and `/me`), and Cognito **access
  tokens do not carry those** — only the **ID token** does. The HTTP API JWT authorizer accepts it
  (`aud` = the app client id). The iOS client (C1) and the runbook should state this explicitly.
- **Cognito pool uses email as the username.** `signInAliases: { email: true }` ⇒
  `UsernameAttributes: [email]`, so `admin-create-user` etc. must pass the email as `--username`.
- **Repo Go-version pinning.** `shared/go-common` is pinned to `go 1.23.7`, held there by pinning
  `testcontainers-go@v0.35.0` plus several transitive deps (smithy-go, otel, klauspost/compress).
  Renovate may try to bump these and re-raise the `go` directive. The clean fix is to standardize the
  whole repo on **Go 1.24** (CI already uses 1.24; `shared/types-go` is already `go 1.24.3`), which
  lets `go-common` use current testcontainers without the pins.

## Operational

- A few **orphaned care-group rows** remain in the **dev** DynamoDB tables from the B1 deploy smoke
  (the Cognito test users were deleted; their care groups/memberships were not). Dev-only test data —
  safe to ignore or sweep.
