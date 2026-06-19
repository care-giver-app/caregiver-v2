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

## iOS (C1-UI) — observed bugs (reported 2026-06-19)

Surfaced during manual use of the C1-UI build; not yet fixed. Both pre-date the home refinement
(PR #23) — captured here to track.

- **Logging an event shows two entries.** After saving in `LogEventView`, the reading appears twice
  in the tracker history. _What was ruled out:_ the client submits once — `LogEventModel.submit`
  (`ios/Caregiver/Events/LogEventModel.swift`) sets `isBusy` before the `await` and the Save button is
  `.disabled(model.isBusy)`, so a single tap = one `logEvent` POST. _Remaining suspects:_ (1) a
  duplicate write server-side / missing idempotency on `POST /trackers/{id}/events`; (2) the history
  pager appends `items + page.items` with **no de-dup by `eventId`** in
  `TrackerDetailModel.loadMoreIfNeeded` (`ios/Caregiver/Trackers/TrackerDetailModel.swift`), so a
  freshly-inserted row that shifts the cursor window can re-surface the boundary item — but this only
  triggers above one page (`pageSize = 25`), so it does **not** explain a duplicate on a tracker with
  few readings. _Fix:_ reproduce to confirm which; if display-side, key/merge history by `eventId`; if
  a double write, add idempotency. _Needs a repro to pin down._
- **Archived receiver still appears in the Home dropdown and in Settings.** Archiving a receiver in
  `ReceiverDetailView` calls `archiveReceiver` then `dismiss()` but never refreshes the shared
  `ReceiverContext`. Both the Home receiver switcher and `SettingsView` render from
  `context.receivers` (filtered on `!archived` only at load time), so the archived receiver lingers
  until the next full context reload; `context.activeReceiver` can also still resolve to it. _Fix:_
  have the archive action call `context.load(using:)` (analogous to how add-receiver does), and
  clear/reselect `activeReceiverID` if the archived receiver was active. _Likely the same
  stale-shared-state class of bug to watch for wherever a mutation isn't followed by a context
  reload._

## iOS (C1-UI) — deferred enhancements

- **Home tracker cards should show the most recent reading + relative timestamp.** Today each glass
  `TrackerCard` (`ios/Caregiver/Home/HomeView.swift`) shows only name + kind. Surfacing the last
  logged value and "how long ago" on Home directly serves the core use case (a caregiver checking
  "when was this last done / what was the value" several times a day) and would otherwise require a
  tap into `TrackerDetailView`. _Keep it to one compact line to avoid clutter:_ a single summary
  string via the existing `DynamicFormBuilder.display(values:fields:)` (already used in `EventRow`) +
  a **relative** time ("2h ago" / "Yesterday" / "Mar 3"); show a quiet "No readings yet" when empty;
  likely **omit free-text notes** on the card (keep them in detail). _The real cost — why this is
  bigger than a layout tweak:_ the `Tracker` schema and the `listTrackers` response carry **no**
  latest-event data (`shared/openapi/openapi.yaml` → `Tracker`), so a data source is needed:
  - **A (recommended):** add a `last_event` summary (occurred_at + values + note) to the tracker in
    the list response — OpenAPI + Go handler + codegen. One request, cacheable, fits the existing
    denormalization pattern.
  - **B (quick):** client fetches `listEvents(limit: 1)` per tracker (N+1). No backend work; tolerable
    at family scale but bloats `HomeModel` and adds latency — would want to retire it later.
    _Trigger:_ when polishing Home / when the design pass reaches the tracker card. Take through
    brainstorm → spec → plan when picked up.

## Operational

- A few **orphaned care-group rows** remain in the **dev** DynamoDB tables from the B1 deploy smoke
  (the Cognito test users were deleted; their care groups/memberships were not). Dev-only test data —
  safe to ignore or sweep.
