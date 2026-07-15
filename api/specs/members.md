# Care-Group Members

- **Module:** api
- **Status:** Current
- **Last updated:** 2026-06-20
- **Contract:** `GET /care-groups/{careGroupId}/members` → array of `Member` (new op + schema in `shared/openapi/openapi.yaml`)
- **Related specs:** B1 data model & identity (`docs/specs/2026-06-11-b1-data-model-identity-design.md`); consumed by [[event-detail]] (ios)

> Living, conceptual spec for one module (api). The interface to clients is owned by the OpenAPI
> contract; this spec references it but never duplicates it.

## Purpose

Lets any care-group member see who else is on the team — a list of members with their **display
names**, ids, and roles. The immediate consumer is the iOS event-detail screen, which needs to turn
an event's `logged_by` user id into a human name ("Logged by Trevor"). It also lays the groundwork
for broader care-team visibility (member lists, future attribution elsewhere).

## Behavior

`GET /care-groups/{careGroupId}/members` returns every membership of the named care group, each
resolved to the member's display name:

- **Authorization:** `RequireMember` — any member of the group may list its members; non-members get
  `403`. (Not admin-gated: seeing your teammates is a baseline member capability.)
- **Response:** an array of `Member { user_id, name, role }`, one per membership.
- **Name resolution:** query memberships by group (`MembershipStore.ListByGroup`, backed by the
  existing `groupIndex` GSI), then batch-resolve each `user_id` to its `User.name` — the same
  membership→user pattern `me.go` already uses to resolve group names.
- **Ordering:** unspecified/stable; the family-scale member count is tiny, so the client sorts or
  looks up by id as needed.
- **Errors:** `401` if unauthenticated, `403` if not a member, `500` on store failure (via the
  shared `httpx` helpers).

No new table, GSI, or write path — this is a read over data B1 already stores.

## Key decisions

| Decision        | Choice                                                | Why                                                                                           |
| --------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Authz level     | `RequireMember`, not `RequireAdmin`                   | Seeing who is on your care team is a baseline member capability, not an admin action          |
| Resolution path | `ListByGroup` (group GSI) → batch-get `User.name`     | Reuses existing store methods + the `me.go` membership→user resolution pattern; no new index  |
| Response shape  | `{ user_id, name, role }` per member                  | Exactly what the client needs to attribute events and show a roster; role is cheap and useful |
| Why it exists   | Driven by [[event-detail]] needing `logged_by` → name | There was no id→name lookup for teammates; this is the contract seam that unblocks real names |
| Scope           | Read-only list; no add/remove members here            | Membership mutation already lives in the invitations flow; this endpoint is purely a read     |

> **Routes are registered in two places.** The HTTP API uses **explicit per-route** registration:
> a new path must be added to BOTH the Go mux (`api/cmd/lambda/mux.go`) AND the CDK `authedRoutes`
> list (`infra/lib/api-stack.ts`). A route present only in the Go mux returns **404** at the API
> Gateway (it never reaches the Lambda). This endpoint shipped mux-only at first, so `listMembers`
> 404'd and the iOS "Logged by" line fell back to the placeholder name until the CDK route was added.

## Where it lives

| Concept                          | File                                                   |
| -------------------------------- | ------------------------------------------------------ |
| Handler: authz + resolve + JSON  | `api/internal/handlers/members.go`                     |
| Route wiring (Go mux)            | `api/cmd/lambda/mux.go`                                |
| Route wiring (API Gateway / CDK) | `infra/lib/api-stack.ts` (`authedRoutes`)              |
| Membership query (existing)      | `shared/go-common/store/membership.go` (`ListByGroup`) |
| User name lookup (existing)      | `shared/go-common/store/user.go` (`Get` / batch)       |
| Contract: operation + `Member`   | `shared/openapi/openapi.yaml`                          |
| Handler tests                    | `api/internal/handlers/members_test.go`                |
| Route registration test          | `infra/test/api-stack.test.ts`                         |

## Non-goals

- No member add/remove/role-change — mutation stays in the invitations flow.
- No pagination — family-scale member counts are tiny.
- No email or other PII beyond name + role in the response.
- No new table or GSI — pure read over existing B1 data.
