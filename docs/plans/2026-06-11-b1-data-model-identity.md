# B1 — Data Model & Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the multi-tenant data model and identity foundation for Caregiver v2 — a `CareGroup` tenant, four DynamoDB tables, Cognito + JIT user provisioning, structural authorization isolation, and the five identity/membership endpoints that prove it end-to-end.

**Architecture:** Extends the F1 scaffolding. OpenAPI 3 stays the contract source of truth (`shared/openapi/openapi.yaml`); Go types regenerate from it. Domain models, DynamoDB repositories, and the authorization primitive live in `shared/go-common/` (reused by B3/B2). HTTP handlers + auth middleware live in `api/`. Tables, the Cognito user pool, and the HTTP API JWT authorizer are CDK (`infra/`). Identity is provisioned just-in-time in middleware from verified JWT claims; every group-scoped request authorizes against the caller's memberships.

**Tech Stack:** Go 1.23, `aws-sdk-go-v2` (DynamoDB), `aws-lambda-go-api-proxy` (already present), `oapi-codegen` (already present), AWS CDK 2.x (TypeScript), Amazon Cognito, API Gateway HTTP API JWT authorizer, DynamoDB + testcontainers (`amazon/dynamodb-local`) for integration tests.

**Spec:** `docs/specs/2026-06-11-b1-data-model-identity-design.md`. **Roadmap:** `docs/roadmap.md`.

---

## Conventions for this plan

- **Module paths:** `github.com/care-giver-app/caregiver-v2/{api,shared/go-common,shared/types-go}`. The `api` module already has a `replace` directive for `go-common`; nothing new there.
- **Table names:** `caregiver-{stage}-<entity>` per ADR-0011. In tests, names are injectable so a test can use unique/local names.
- **Each task ends with an `Acceptance Criteria` block** — concrete, checkable conditions to validate the task is done without reading the implementation. These ladder up to spec §13.
- **Commit discipline:** Conventional Commits; commitlint requires a lowercase subject start (e.g. `feat: add ...`, not `feat: Add ...`). Pre-commit runs Prettier on staged TS/JSON/MD/YAML.
- **Stage gate:** all Go work is validated locally + in CI against DynamoDB Local; Cognito/JWT-authorizer behavior is validated by a one-time deployed-dev smoke (Task 18), since it can't be exercised against DynamoDB Local alone.

## File-structure map

**Created in `shared/go-common/`:**

| File                             | Responsibility                                                                                                     |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `domain/models.go`               | Pure types: `User`, `CareGroup`, `Membership`, `Invitation`, `Role`, plus invite-token generation. No AWS imports. |
| `domain/models_test.go`          | Token randomness/format, role validity, email normalization.                                                       |
| `store/store.go`                 | `Stores` aggregate + shared DynamoDB client construction (endpoint-injectable for tests).                          |
| `store/user.go`                  | `UserStore`: get-by-id, conditional create (JIT).                                                                  |
| `store/caregroup.go`             | `CareGroupStore`: get, create.                                                                                     |
| `store/membership.go`            | `MembershipStore`: list-by-user, list-by-group (GSI), transactional create.                                        |
| `store/invitation.go`            | `InvitationStore`: get-by-token, list-by-email (GSI), list-by-group (GSI), create, transactional accept, revoke.   |
| `store/*_test.go`                | Integration tests per store against DynamoDB Local.                                                                |
| `store/dynamotest/dynamotest.go` | Test helper: start `amazon/dynamodb-local` via testcontainers, create the 4 tables, return a client + table names. |
| `auth/context.go`                | `AuthContext`, `Memberships`, `RequireMember`/`RequireAdmin`, request-context get/set helpers.                     |
| `auth/context_test.go`           | Unit tests for the authorization predicates.                                                                       |

**Created/modified in `api/`:**

| File                                        | Responsibility                                                                                                                 |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `internal/middleware/auth.go`               | Extract verified claims from the APIGW v2 authorizer context → JIT-provision `User` → load memberships → attach `AuthContext`. |
| `internal/middleware/auth_test.go`          | JIT create/no-op/race; claims missing → 401.                                                                                   |
| `internal/handlers/me.go` (+ test)          | `GET /me`.                                                                                                                     |
| `internal/handlers/caregroups.go` (+ test)  | `POST /care-groups`, `POST /care-groups/{id}/invitations`, `DELETE …/invitations/{token}`.                                     |
| `internal/handlers/invitations.go` (+ test) | `GET /invitations/mine`, `POST /invitations/{token}/accept`.                                                                   |
| `internal/handlers/isolation_test.go`       | The cross-tenant isolation suite (security gate).                                                                              |
| `cmd/lambda/mux.go` (modify)                | Wire the new handlers + middleware with real stores.                                                                           |

**Modified in `shared/`:**

| File                                 | Responsibility                                           |
| ------------------------------------ | -------------------------------------------------------- |
| `openapi/openapi.yaml`               | Add bearer security scheme, B1 schemas, and the 6 paths. |
| `types-go/caregiverapi/types.gen.go` | Regenerated (do not hand-edit).                          |
| `types-swift/`                       | Regenerated Swift client (Task 2).                       |

**Modified in `infra/`:**

| File                                                  | Responsibility                                                                                                 |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `lib/shared-stack.ts`                                 | 4 DynamoDB tables (+ GSIs + TTL) and a Cognito user pool + app client; expose names/IDs.                       |
| `lib/api-stack.ts`                                    | JWT authorizer on the HTTP API; the 6 new routes; DynamoDB grants + table-name/Cognito env vars on the Lambda. |
| `bin/app.ts` (modify)                                 | Pass the new SharedStack outputs into ApiStack props.                                                          |
| `test/shared-stack.test.ts`, `test/api-stack.test.ts` | Assertions for the new resources.                                                                              |

---

## Section 1 — Contract first (OpenAPI + codegen)

### Task 1: Extend the OpenAPI contract with B1 schemas, security, and paths

**Files:**

- Modify: `shared/openapi/openapi.yaml`

- [ ] **Step 1.1: Add a bearer security scheme and apply it by default**

In `shared/openapi/openapi.yaml`, under `components`, add a `securitySchemes` block, and add a top-level `security` default (health already opts out with `security: []`).

Add at the top level (after `servers:`):

```yaml
security:
  - bearerAuth: []
```

Under `components:` (sibling to `schemas:`):

```yaml
securitySchemes:
  bearerAuth:
    type: http
    scheme: bearer
    bearerFormat: JWT
    description: Cognito-issued JWT access token, validated by the API Gateway JWT authorizer.
```

- [ ] **Step 1.2: Add the B1 schemas**

Under `components.schemas`, add:

```yaml
Role:
  type: string
  enum: [admin, caregiver]
User:
  type: object
  required: [user_id, email, name, created_at]
  properties:
    user_id: { type: string }
    email: { type: string, format: email }
    name: { type: string }
    created_at: { type: string, format: date-time }
MembershipView:
  type: object
  required: [care_group_id, name, role]
  properties:
    care_group_id: { type: string }
    name: { type: string }
    role: { $ref: '#/components/schemas/Role' }
Me:
  type: object
  required: [user, memberships]
  properties:
    user: { $ref: '#/components/schemas/User' }
    memberships:
      type: array
      items: { $ref: '#/components/schemas/MembershipView' }
CreateCareGroupRequest:
  type: object
  required: [name]
  properties:
    name: { type: string, minLength: 1, maxLength: 100 }
CareGroupMembership:
  type: object
  required: [care_group_id, name, role]
  properties:
    care_group_id: { type: string }
    name: { type: string }
    role: { $ref: '#/components/schemas/Role' }
CreateInvitationRequest:
  type: object
  required: [email, role]
  properties:
    email: { type: string, format: email }
    role: { $ref: '#/components/schemas/Role' }
Invitation:
  type: object
  required: [token, email, role, expires_at]
  properties:
    token: { type: string }
    email: { type: string, format: email }
    role: { $ref: '#/components/schemas/Role' }
    expires_at: { type: string, format: date-time }
PendingInvitation:
  type: object
  required: [token, care_group_id, care_group_name, role, invited_by]
  properties:
    token: { type: string }
    care_group_id: { type: string }
    care_group_name: { type: string }
    role: { $ref: '#/components/schemas/Role' }
    invited_by: { type: string }
AcceptInvitationResponse:
  type: object
  required: [care_group_id, role]
  properties:
    care_group_id: { type: string }
    role: { $ref: '#/components/schemas/Role' }
Error:
  type: object
  required: [message]
  properties:
    message: { type: string }
```

- [ ] **Step 1.3: Add the six paths**

Under `paths:`, add:

```yaml
/me:
  get:
    operationId: getMe
    summary: Current user and their care-group memberships
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Me' }
      '401': { $ref: '#/components/responses/Unauthorized' }
/care-groups:
  post:
    operationId: createCareGroup
    summary: Create a care group; caller becomes Admin
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/CreateCareGroupRequest' }
    responses:
      '201':
        description: Created
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CareGroupMembership' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
/care-groups/{careGroupId}/invitations:
  post:
    operationId: createInvitation
    summary: Invite a user to the care group by email (admin only)
    parameters:
      - { name: careGroupId, in: path, required: true, schema: { type: string } }
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/CreateInvitationRequest' }
    responses:
      '201':
        description: Created
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Invitation' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '409': { $ref: '#/components/responses/Conflict' }
/care-groups/{careGroupId}/invitations/{token}:
  delete:
    operationId: revokeInvitation
    summary: Revoke a pending invitation (admin only)
    parameters:
      - { name: careGroupId, in: path, required: true, schema: { type: string } }
      - { name: token, in: path, required: true, schema: { type: string } }
    responses:
      '204': { description: No Content }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
/invitations/mine:
  get:
    operationId: listMyInvitations
    summary: Pending invitations for the caller's verified email
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema:
              type: array
              items: { $ref: '#/components/schemas/PendingInvitation' }
      '401': { $ref: '#/components/responses/Unauthorized' }
/invitations/{token}/accept:
  post:
    operationId: acceptInvitation
    summary: Accept an invitation by token; creates a membership
    parameters:
      - { name: token, in: path, required: true, schema: { type: string } }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/AcceptInvitationResponse' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '404': { $ref: '#/components/responses/NotFound' }
      '410': { $ref: '#/components/responses/Gone' }
```

- [ ] **Step 1.4: Add the shared error responses**

Under `components:`, add a `responses:` block:

```yaml
responses:
  BadRequest:
    description: Bad request
    content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
  Unauthorized:
    description: Missing or invalid token
    content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
  Forbidden:
    description: Not permitted
    content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
  NotFound:
    description: Not found
    content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
  Conflict:
    description: Conflict (duplicate)
    content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
  Gone:
    description: Invitation expired or already used
    content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
```

- [ ] **Step 1.5: Lint the spec**

Run: `pnpm --filter @caregiver/openapi run lint` (if a lint script exists) or `pnpm exec prettier --check shared/openapi/openapi.yaml`.
Expected: passes (apply `--write` if Prettier reflows it, then re-check).

**Acceptance Criteria — Task 1:**

- `shared/openapi/openapi.yaml` parses as valid OpenAPI 3.0.3 (no `$ref` resolves to a missing component).
- All six B1 operations are present with the `operationId`s above and each non-health operation requires `bearerAuth` (inherited from the top-level `security`).
- Prettier check passes on the file.

---

### Task 2: Regenerate Go (and Swift) types from the contract

**Files:**

- Modify: `shared/types-go/caregiverapi/types.gen.go` (generated)
- Modify: `shared/types-swift/` generated output (generated)

- [ ] **Step 2.1: Regenerate Go types**

Run: `cd shared/types-go && make codegen`
Expected: `caregiverapi/types.gen.go` now contains generated structs `User`, `Me`, `MembershipView`, `CreateCareGroupRequest`, `CareGroupMembership`, `CreateInvitationRequest`, `Invitation`, `PendingInvitation`, `AcceptInvitationResponse`, `Error`, and a `Role` type with `Admin`/`Caregiver` constants.

- [ ] **Step 2.2: Verify the Go types compile**

Run: `cd shared/types-go && go build ./...`
Expected: builds with no errors.

- [ ] **Step 2.3: Regenerate the Swift client**

Run the Swift generation per `shared/types-swift/` setup: `cd shared/types-swift && swift build` (the swift-openapi-generator plugin regenerates on build).
Expected: builds; generated client gains the new operations. If Swift/Xcode is unavailable on this machine, mark this step blocked and note it for the C1 (iOS) phase — it does not block the Go-side B1 work.

- [ ] **Step 2.4: Commit the contract + generated types**

```bash
git add shared/openapi/openapi.yaml shared/types-go/caregiverapi/types.gen.go shared/types-swift
git commit -m "feat(contract): add B1 identity and care-group endpoints"
```

**Acceptance Criteria — Task 2:**

- `go build ./...` in `shared/types-go` succeeds and the named structs exist.
- `git diff --stat` shows only generated files + the contract changed (no hand-edits to `types.gen.go`).
- Swift client regenerates, or the step is explicitly recorded as blocked-on-toolchain for C1.

---

## Section 2 — Domain model & DynamoDB stores (`shared/go-common`)

> These tests require Docker (testcontainers + `amazon/dynamodb-local`), consistent with ADR-0006.
> Store tests are tagged so they can be skipped where Docker is unavailable.

### Task 3: Domain models + invite-token generation

**Files:**

- Create: `shared/go-common/domain/models.go`
- Test: `shared/go-common/domain/models_test.go`

- [ ] **Step 3.1: Write the failing test**

Create `shared/go-common/domain/models_test.go`:

```go
package domain

import (
	"testing"
	"time"
)

func TestNewInviteToken_isRandomAndURLSafe(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 100; i++ {
		tok, err := NewInviteToken()
		if err != nil {
			t.Fatalf("NewInviteToken: %v", err)
		}
		if len(tok) < 20 {
			t.Fatalf("token too short: %q", tok)
		}
		for _, r := range tok {
			if !(r == '-' || r == '_' || (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')) {
				t.Fatalf("token not URL-safe: %q", tok)
			}
		}
		if seen[tok] {
			t.Fatalf("duplicate token: %q", tok)
		}
		seen[tok] = true
	}
}

func TestRole_Valid(t *testing.T) {
	if !RoleAdmin.Valid() || !RoleCaregiver.Valid() {
		t.Fatal("admin/caregiver should be valid")
	}
	if Role("owner").Valid() {
		t.Fatal("owner should be invalid")
	}
}

func TestNormalizeEmail(t *testing.T) {
	if got := NormalizeEmail("  Foo@Bar.COM "); got != "foo@bar.com" {
		t.Fatalf("got %q", got)
	}
}

func TestInvitation_Expired(t *testing.T) {
	now := time.Unix(1000, 0)
	if (Invitation{ExpiresAt: 1001}).Expired(now) {
		t.Fatal("not expired yet")
	}
	if !(Invitation{ExpiresAt: 1000}).Expired(now) {
		t.Fatal("should be expired at boundary")
	}
}
```

- [ ] **Step 3.2: Run, expect FAIL (package does not compile)**

Run: `cd shared/go-common && go test ./domain/...`
Expected: FAIL — undefined `NewInviteToken`, `Role`, etc.

- [ ] **Step 3.3: Implement `domain/models.go`**

Create `shared/go-common/domain/models.go`:

```go
// Package domain holds the B1 entity types and pure helpers. No AWS imports.
package domain

import (
	"crypto/rand"
	"encoding/base64"
	"strings"
	"time"
)

type Role string

const (
	RoleAdmin     Role = "admin"
	RoleCaregiver Role = "caregiver"
)

func (r Role) Valid() bool { return r == RoleAdmin || r == RoleCaregiver }

type User struct {
	UserID    string    `dynamodbav:"user_id"`
	Email     string    `dynamodbav:"email"`
	Name      string    `dynamodbav:"name"`
	CreatedAt time.Time `dynamodbav:"created_at"`
}

type CareGroup struct {
	CareGroupID string    `dynamodbav:"care_group_id"`
	Name        string    `dynamodbav:"name"`
	CreatedBy   string    `dynamodbav:"created_by"`
	CreatedAt   time.Time `dynamodbav:"created_at"`
}

type Membership struct {
	UserID      string    `dynamodbav:"user_id"`
	CareGroupID string    `dynamodbav:"care_group_id"`
	Role        Role      `dynamodbav:"role"`
	CreatedAt   time.Time `dynamodbav:"created_at"`
}

type InvitationStatus string

const (
	InvitePending  InvitationStatus = "pending"
	InviteAccepted InvitationStatus = "accepted"
	InviteRevoked  InvitationStatus = "revoked"
)

type Invitation struct {
	Token       string           `dynamodbav:"token"`
	CareGroupID string           `dynamodbav:"care_group_id"`
	Email       string           `dynamodbav:"email"`
	Role        Role             `dynamodbav:"role"`
	Status      InvitationStatus `dynamodbav:"status"`
	InvitedBy   string           `dynamodbav:"invited_by"`
	CreatedAt   time.Time        `dynamodbav:"created_at"`
	ExpiresAt   int64            `dynamodbav:"expires_at"` // unix seconds; DynamoDB TTL attribute
}

// Expired reports whether the invitation is at or past its expiry.
func (i Invitation) Expired(now time.Time) bool { return now.Unix() >= i.ExpiresAt }

// NormalizeEmail lowercases and trims for consistent matching.
func NormalizeEmail(email string) string { return strings.ToLower(strings.TrimSpace(email)) }

// NewInviteToken returns a URL-safe, 128-bit random single-use token.
func NewInviteToken() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
```

- [ ] **Step 3.4: Run, expect PASS**

Run: `cd shared/go-common && go test ./domain/...`
Expected: PASS.

- [ ] **Step 3.5: Commit**

```bash
git add shared/go-common/domain
git commit -m "feat(domain): B1 entity types and invite-token generation"
```

**Acceptance Criteria — Task 3:**

- `go test ./domain/...` passes in `shared/go-common`.
- `NewInviteToken` yields URL-safe, non-repeating tokens; `Role.Valid`, `NormalizeEmail`, and `Invitation.Expired` behave as tested.
- `domain` imports no AWS packages (`go list -deps ./domain | grep aws-sdk` returns nothing).

---

### Task 4: DynamoDB client + test harness

**Files:**

- Create: `shared/go-common/store/store.go`
- Create: `shared/go-common/store/dynamotest/dynamotest.go`

- [ ] **Step 4.1: Add dependencies**

```bash
cd shared/go-common
go get github.com/aws/aws-sdk-go-v2/aws@latest
go get github.com/aws/aws-sdk-go-v2/config@latest
go get github.com/aws/aws-sdk-go-v2/service/dynamodb@latest
go get github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue@latest
go get github.com/testcontainers/testcontainers-go@latest
```

Expected: `shared/go-common/go.mod` now lists these requires.

- [ ] **Step 4.2: Write `store/store.go` (client + aggregate)**

Create `shared/go-common/store/store.go`:

```go
// Package store holds the DynamoDB repositories for the B1 entities.
package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

// ErrNotFound is returned by Get methods when no item exists.
var ErrNotFound = errors.New("not found")

// TableNames holds the four B1 table names.
type TableNames struct {
	Users       string
	CareGroups  string
	Memberships string
	Invitations string
}

// Stores aggregates the per-entity repositories and owns cross-table transactions.
type Stores struct {
	client *dynamodb.Client
	names  TableNames

	Users       *UserStore
	CareGroups  *CareGroupStore
	Memberships *MembershipStore
	Invitations *InvitationStore
}

const (
	groupIndex = "group-index"
	emailIndex = "email-index"
)

// New builds Stores from a DynamoDB client and table names.
func New(client *dynamodb.Client, names TableNames) *Stores {
	return &Stores{
		client:      client,
		names:       names,
		Users:       &UserStore{client: client, table: names.Users},
		CareGroups:  &CareGroupStore{client: client, table: names.CareGroups},
		Memberships: &MembershipStore{client: client, table: names.Memberships},
		Invitations: &InvitationStore{client: client, table: names.Invitations},
	}
}

// NewClient builds a DynamoDB client. A non-empty endpoint (tests/local) overrides
// the resolved endpoint.
func NewClient(ctx context.Context, endpoint string) (*dynamodb.Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	return dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
	}), nil
}
```

- [ ] **Step 4.3: Write the test harness `store/dynamotest/dynamotest.go`**

Create `shared/go-common/store/dynamotest/dynamotest.go`:

```go
// Package dynamotest spins up DynamoDB Local and creates the B1 tables for tests.
package dynamotest

import (
	"context"
	"fmt"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

// Start launches DynamoDB Local, creates the four tables (with GSIs), and returns
// Stores wired to it. The container is terminated via t.Cleanup.
func Start(t *testing.T) *store.Stores {
	t.Helper()
	ctx := context.Background()

	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "amazon/dynamodb-local:2.5.2",
			ExposedPorts: []string{"8000/tcp"},
			WaitingFor:   wait.ForListeningPort("8000/tcp"),
		},
		Started: true,
	})
	if err != nil {
		t.Fatalf("start dynamodb-local: %v", err)
	}
	t.Cleanup(func() { _ = container.Terminate(ctx) })

	host, err := container.Host(ctx)
	if err != nil {
		t.Fatalf("host: %v", err)
	}
	port, err := container.MappedPort(ctx, "8000")
	if err != nil {
		t.Fatalf("port: %v", err)
	}
	endpoint := fmt.Sprintf("http://%s:%s", host, port.Port())

	// DynamoDB Local ignores credentials but the SDK requires them to be present.
	t.Setenv("AWS_ACCESS_KEY_ID", "local")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "local")
	t.Setenv("AWS_REGION", "us-east-2")

	client, err := store.NewClient(ctx, endpoint)
	if err != nil {
		t.Fatalf("client: %v", err)
	}

	names := store.TableNames{
		Users:       "test-user",
		CareGroups:  "test-care-group",
		Memberships: "test-membership",
		Invitations: "test-invitation",
	}
	createTables(t, ctx, client, names)
	return store.New(client, names)
}

func createTables(t *testing.T, ctx context.Context, c *dynamodb.Client, n store.TableNames) {
	t.Helper()
	mustCreate := func(in *dynamodb.CreateTableInput) {
		if _, err := c.CreateTable(ctx, in); err != nil {
			t.Fatalf("create table %s: %v", *in.TableName, err)
		}
	}

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Users),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("user_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("email"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("user_id"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName:  aws.String("email-index"),
			KeySchema:  []types.KeySchemaElement{{AttributeName: aws.String("email"), KeyType: types.KeyTypeHash}},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.CareGroups),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash},
		},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Memberships),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("user_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("user_id"), KeyType: types.KeyTypeHash},
			{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeRange},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("group-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("user_id"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Invitations),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("token"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("email"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("token"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{
			{
				IndexName:  aws.String("group-index"),
				KeySchema:  []types.KeySchemaElement{{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash}},
				Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
			},
			{
				IndexName:  aws.String("email-index"),
				KeySchema:  []types.KeySchemaElement{{AttributeName: aws.String("email"), KeyType: types.KeyTypeHash}},
				Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
			},
		},
	})
}
```

- [ ] **Step 4.4: Verify it compiles**

Run: `cd shared/go-common && go build ./...`
Expected: builds (no test run yet — exercised by Task 5).

- [ ] **Step 4.5: Commit**

```bash
git add shared/go-common/store/store.go shared/go-common/store/dynamotest shared/go-common/go.mod shared/go-common/go.sum
git commit -m "feat(store): DynamoDB client and DynamoDB-Local test harness"
```

**Acceptance Criteria — Task 4:**

- `go build ./...` in `shared/go-common` succeeds.
- `dynamotest.Start` creates four tables whose key schema + GSIs match spec §5 (`user`/`email-index`, `membership` PK+SK / `group-index`, `invitation` PK `token` / `group-index` + `email-index`).
- `store.NewClient` honors a non-empty endpoint override.

---

### Task 5: UserStore (Get + JIT conditional create)

**Files:**

- Create: `shared/go-common/store/user.go`
- Test: `shared/go-common/store/user_test.go`

- [ ] **Step 5.1: Write the failing test**

Create `shared/go-common/store/user_test.go`:

```go
package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestUserStore_CreateIfAbsent_andGet(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	u := domain.User{UserID: "sub-1", Email: "a@b.com", Name: "A", CreatedAt: time.Now().UTC().Truncate(time.Second)}

	created, err := s.Users.CreateIfAbsent(ctx, u)
	if err != nil || !created {
		t.Fatalf("first create: created=%v err=%v", created, err)
	}

	// Second create is a no-op (idempotent JIT), not an error.
	created2, err := s.Users.CreateIfAbsent(ctx, domain.User{UserID: "sub-1", Email: "x@y.com", Name: "X"})
	if err != nil || created2 {
		t.Fatalf("second create: created=%v err=%v", created2, err)
	}

	got, err := s.Users.Get(ctx, "sub-1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Email != "a@b.com" { // original row preserved
		t.Fatalf("expected original email, got %q", got.Email)
	}

	if _, err := s.Users.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
```

- [ ] **Step 5.2: Run, expect FAIL**

Run: `cd shared/go-common && go test ./store/ -run TestUserStore`
Expected: FAIL — undefined `UserStore` methods.

- [ ] **Step 5.3: Implement `store/user.go`**

Create `shared/go-common/store/user.go`:

```go
package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type UserStore struct {
	client *dynamodb.Client
	table  string
}

func (s *UserStore) Get(ctx context.Context, userID string) (domain.User, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key:       map[string]types.AttributeValue{"user_id": &types.AttributeValueMemberS{Value: userID}},
	})
	if err != nil {
		return domain.User{}, err
	}
	if out.Item == nil {
		return domain.User{}, ErrNotFound
	}
	var u domain.User
	if err := attributevalue.UnmarshalMap(out.Item, &u); err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// CreateIfAbsent writes the user only if no row exists for the id. It returns
// created=false (no error) if a row already exists — the idempotent JIT path.
func (s *UserStore) CreateIfAbsent(ctx context.Context, u domain.User) (bool, error) {
	item, err := attributevalue.MarshalMap(u)
	if err != nil {
		return false, err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(user_id)"),
	})
	if err != nil {
		var ccf *types.ConditionalCheckFailedException
		if errors.As(err, &ccf) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}
```

- [ ] **Step 5.4: Run, expect PASS**

Run: `cd shared/go-common && go test ./store/ -run TestUserStore`
Expected: PASS.

- [ ] **Step 5.5: Commit**

```bash
git add shared/go-common/store/user.go shared/go-common/store/user_test.go
git commit -m "feat(store): UserStore with idempotent JIT create"
```

**Acceptance Criteria — Task 5:**

- First `CreateIfAbsent` returns `created=true`; a second call for the same `user_id` returns `created=false, err=nil` and does **not** overwrite the original row.
- `Get` returns `ErrNotFound` for an unknown id.

---

### Task 6: CareGroupStore (Get + BatchGet)

**Files:**

- Create: `shared/go-common/store/caregroup.go`
- Test: `shared/go-common/store/caregroup_test.go`

- [ ] **Step 6.1: Write the failing test**

Create `shared/go-common/store/caregroup_test.go`:

```go
package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestCareGroupStore_BatchGet(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()

	// Seed two groups via the transactional create (also exercises Task 7 wiring).
	for _, g := range []domain.CareGroup{
		{CareGroupID: "g1", Name: "One", CreatedBy: "u1", CreatedAt: time.Now().UTC()},
		{CareGroupID: "g2", Name: "Two", CreatedBy: "u1", CreatedAt: time.Now().UTC()},
	} {
		m := domain.Membership{UserID: "u1", CareGroupID: g.CareGroupID, Role: domain.RoleAdmin, CreatedAt: time.Now().UTC()}
		if err := s.CreateCareGroupWithAdmin(ctx, g, m); err != nil {
			t.Fatalf("seed %s: %v", g.CareGroupID, err)
		}
	}

	got, err := s.CareGroups.BatchGet(ctx, []string{"g1", "g2", "missing"})
	if err != nil {
		t.Fatalf("batchget: %v", err)
	}
	if len(got) != 2 || got["g1"].Name != "One" || got["g2"].Name != "Two" {
		t.Fatalf("unexpected: %+v", got)
	}
}
```

- [ ] **Step 6.2: Run, expect FAIL**

Run: `cd shared/go-common && go test ./store/ -run TestCareGroupStore`
Expected: FAIL — undefined `CareGroupStore.BatchGet` / `Stores.CreateCareGroupWithAdmin`.

- [ ] **Step 6.3: Implement `store/caregroup.go`**

Create `shared/go-common/store/caregroup.go`:

```go
package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type CareGroupStore struct {
	client *dynamodb.Client
	table  string
}

func (s *CareGroupStore) Get(ctx context.Context, id string) (domain.CareGroup, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key:       map[string]types.AttributeValue{"care_group_id": &types.AttributeValueMemberS{Value: id}},
	})
	if err != nil {
		return domain.CareGroup{}, err
	}
	if out.Item == nil {
		return domain.CareGroup{}, ErrNotFound
	}
	var g domain.CareGroup
	if err := attributevalue.UnmarshalMap(out.Item, &g); err != nil {
		return domain.CareGroup{}, err
	}
	return g, nil
}

// BatchGet returns the care groups for the given ids, keyed by id. Missing ids
// are simply absent from the result.
func (s *CareGroupStore) BatchGet(ctx context.Context, ids []string) (map[string]domain.CareGroup, error) {
	result := make(map[string]domain.CareGroup, len(ids))
	if len(ids) == 0 {
		return result, nil
	}
	keys := make([]map[string]types.AttributeValue, 0, len(ids))
	for _, id := range ids {
		keys = append(keys, map[string]types.AttributeValue{"care_group_id": &types.AttributeValueMemberS{Value: id}})
	}
	out, err := s.client.BatchGetItem(ctx, &dynamodb.BatchGetItemInput{
		RequestItems: map[string]types.KeysAndAttributes{s.table: {Keys: keys}},
	})
	if err != nil {
		return nil, err
	}
	for _, item := range out.Responses[s.table] {
		var g domain.CareGroup
		if err := attributevalue.UnmarshalMap(item, &g); err != nil {
			return nil, err
		}
		result[g.CareGroupID] = g
	}
	return result, nil
}
```

(`Stores.CreateCareGroupWithAdmin` is implemented in Task 7 alongside the membership transaction; this test goes green at the end of Task 7. Run it again then.)

- [ ] **Step 6.4: Commit**

```bash
git add shared/go-common/store/caregroup.go shared/go-common/store/caregroup_test.go
git commit -m "feat(store): CareGroupStore get + batch-get"
```

**Acceptance Criteria — Task 6:**

- After Task 7, `TestCareGroupStore_BatchGet` passes.
- `BatchGet` returns only found ids and never errors on missing ids.

---

### Task 7: MembershipStore + the create-group transaction

**Files:**

- Create: `shared/go-common/store/membership.go`
- Create: `shared/go-common/store/transactions.go`
- Test: `shared/go-common/store/membership_test.go`

- [ ] **Step 7.1: Write the failing test**

Create `shared/go-common/store/membership_test.go`:

```go
package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestMembership_createGroupAndQueries(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	g := domain.CareGroup{CareGroupID: "g1", Name: "One", CreatedBy: "u1", CreatedAt: now}
	admin := domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now}
	if err := s.CreateCareGroupWithAdmin(ctx, g, admin); err != nil {
		t.Fatalf("create group: %v", err)
	}
	// add a second member directly
	if err := s.Memberships.Put(ctx, domain.Membership{UserID: "u2", CareGroupID: "g1", Role: domain.RoleCaregiver, CreatedAt: now}); err != nil {
		t.Fatalf("put member: %v", err)
	}

	byUser, err := s.Memberships.ListByUser(ctx, "u1")
	if err != nil || len(byUser) != 1 || byUser[0].Role != domain.RoleAdmin {
		t.Fatalf("ListByUser: %+v err=%v", byUser, err)
	}
	byGroup, err := s.Memberships.ListByGroup(ctx, "g1")
	if err != nil || len(byGroup) != 2 {
		t.Fatalf("ListByGroup: %+v err=%v", byGroup, err)
	}
}
```

- [ ] **Step 7.2: Run, expect FAIL**

Run: `cd shared/go-common && go test ./store/ -run TestMembership`
Expected: FAIL — undefined methods.

- [ ] **Step 7.3: Implement `store/membership.go`**

Create `shared/go-common/store/membership.go`:

```go
package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type MembershipStore struct {
	client *dynamodb.Client
	table  string
}

func (s *MembershipStore) Put(ctx context.Context, m domain.Membership) error {
	item, err := attributevalue.MarshalMap(m)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *MembershipStore) Get(ctx context.Context, userID, careGroupID string) (domain.Membership, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key: map[string]types.AttributeValue{
			"user_id":       &types.AttributeValueMemberS{Value: userID},
			"care_group_id": &types.AttributeValueMemberS{Value: careGroupID},
		},
	})
	if err != nil {
		return domain.Membership{}, err
	}
	if out.Item == nil {
		return domain.Membership{}, ErrNotFound
	}
	var m domain.Membership
	if err := attributevalue.UnmarshalMap(out.Item, &m); err != nil {
		return domain.Membership{}, err
	}
	return m, nil
}

func (s *MembershipStore) ListByUser(ctx context.Context, userID string) ([]domain.Membership, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		KeyConditionExpression: aws.String("user_id = :u"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":u": &types.AttributeValueMemberS{Value: userID},
		},
	})
	if err != nil {
		return nil, err
	}
	var ms []domain.Membership
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &ms); err != nil {
		return nil, err
	}
	return ms, nil
}

func (s *MembershipStore) ListByGroup(ctx context.Context, careGroupID string) ([]domain.Membership, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(groupIndex),
		KeyConditionExpression: aws.String("care_group_id = :g"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":g": &types.AttributeValueMemberS{Value: careGroupID},
		},
	})
	if err != nil {
		return nil, err
	}
	var ms []domain.Membership
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &ms); err != nil {
		return nil, err
	}
	return ms, nil
}
```

- [ ] **Step 7.4: Implement `store/transactions.go`**

Create `shared/go-common/store/transactions.go`:

```go
package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

// CreateCareGroupWithAdmin writes the group and the creator's admin membership
// atomically. The group write is conditional so an id collision fails cleanly.
func (s *Stores) CreateCareGroupWithAdmin(ctx context.Context, g domain.CareGroup, m domain.Membership) error {
	gi, err := attributevalue.MarshalMap(g)
	if err != nil {
		return err
	}
	mi, err := attributevalue.MarshalMap(m)
	if err != nil {
		return err
	}
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{Put: &types.Put{
				TableName:           aws.String(s.names.CareGroups),
				Item:                gi,
				ConditionExpression: aws.String("attribute_not_exists(care_group_id)"),
			}},
			{Put: &types.Put{TableName: aws.String(s.names.Memberships), Item: mi}},
		},
	})
	return err
}
```

- [ ] **Step 7.5: Run, expect PASS (membership + caregroup tests)**

Run: `cd shared/go-common && go test ./store/ -run 'TestMembership|TestCareGroupStore'`
Expected: PASS.

- [ ] **Step 7.6: Commit**

```bash
git add shared/go-common/store/membership.go shared/go-common/store/transactions.go shared/go-common/store/membership_test.go
git commit -m "feat(store): MembershipStore and atomic create-group-with-admin"
```

**Acceptance Criteria — Task 7:**

- `CreateCareGroupWithAdmin` writes both items atomically; `ListByUser` and `ListByGroup` (GSI) return them.
- Re-running `TestCareGroupStore_BatchGet` (Task 6) now passes.

---

### Task 8: InvitationStore + the accept transaction

**Files:**

- Create: `shared/go-common/store/invitation.go`
- Modify: `shared/go-common/store/transactions.go` (add `AcceptInvitation`)
- Test: `shared/go-common/store/invitation_test.go`

- [ ] **Step 8.1: Write the failing test**

Create `shared/go-common/store/invitation_test.go`:

```go
package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestInvitation_createListAccept(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	inv := domain.Invitation{
		Token: "tok-1", CareGroupID: "g1", Email: "invitee@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	}
	if err := s.Invitations.Create(ctx, inv); err != nil {
		t.Fatalf("create: %v", err)
	}

	byEmail, err := s.Invitations.ListPendingByEmail(ctx, "invitee@x.com")
	if err != nil || len(byEmail) != 1 {
		t.Fatalf("ListPendingByEmail: %+v err=%v", byEmail, err)
	}

	// Accept: creates membership and flips status to accepted, atomically.
	mem := domain.Membership{UserID: "u2", CareGroupID: "g1", Role: domain.RoleCaregiver, CreatedAt: now}
	if err := s.AcceptInvitation(ctx, "tok-1", mem); err != nil {
		t.Fatalf("accept: %v", err)
	}
	if m, err := s.Memberships.Get(ctx, "u2", "g1"); err != nil || m.Role != domain.RoleCaregiver {
		t.Fatalf("membership after accept: %+v err=%v", m, err)
	}

	// Second accept fails the pending condition (already accepted).
	err = s.AcceptInvitation(ctx, "tok-1", mem)
	if err == nil {
		t.Fatal("expected second accept to fail the pending condition")
	}

	// Pending-by-email is now empty.
	byEmail, _ = s.Invitations.ListPendingByEmail(ctx, "invitee@x.com")
	if len(byEmail) != 0 {
		t.Fatalf("expected no pending invites, got %d", len(byEmail))
	}

	if _, err := s.Invitations.Get(ctx, "nope"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}
```

- [ ] **Step 8.2: Run, expect FAIL**

Run: `cd shared/go-common && go test ./store/ -run TestInvitation`
Expected: FAIL — undefined methods.

- [ ] **Step 8.3: Implement `store/invitation.go`**

Create `shared/go-common/store/invitation.go`:

```go
package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type InvitationStore struct {
	client *dynamodb.Client
	table  string
}

func (s *InvitationStore) Create(ctx context.Context, inv domain.Invitation) error {
	item, err := attributevalue.MarshalMap(inv)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(#tok)"),
		ExpressionAttributeNames: map[string]string{"#tok": "token"},
	})
	return err
}

func (s *InvitationStore) Get(ctx context.Context, token string) (domain.Invitation, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key:       map[string]types.AttributeValue{"token": &types.AttributeValueMemberS{Value: token}},
	})
	if err != nil {
		return domain.Invitation{}, err
	}
	if out.Item == nil {
		return domain.Invitation{}, ErrNotFound
	}
	var inv domain.Invitation
	if err := attributevalue.UnmarshalMap(out.Item, &inv); err != nil {
		return domain.Invitation{}, err
	}
	return inv, nil
}

func (s *InvitationStore) ListPendingByEmail(ctx context.Context, email string) ([]domain.Invitation, error) {
	return s.queryPending(ctx, emailIndex, "email", email)
}

func (s *InvitationStore) ListPendingByGroup(ctx context.Context, careGroupID string) ([]domain.Invitation, error) {
	return s.queryPending(ctx, groupIndex, "care_group_id", careGroupID)
}

func (s *InvitationStore) queryPending(ctx context.Context, index, keyAttr, keyVal string) ([]domain.Invitation, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(index),
		KeyConditionExpression: aws.String("#k = :v"),
		FilterExpression:       aws.String("#s = :pending"),
		ExpressionAttributeNames: map[string]string{"#k": keyAttr, "#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":v":       &types.AttributeValueMemberS{Value: keyVal},
			":pending": &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
		},
	})
	if err != nil {
		return nil, err
	}
	var invs []domain.Invitation
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &invs); err != nil {
		return nil, err
	}
	return invs, nil
}

// Revoke flips a pending invitation to revoked. Returns ErrNotFound if it isn't pending.
func (s *InvitationStore) Revoke(ctx context.Context, token string) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:           aws.String(s.table),
		Key:                 map[string]types.AttributeValue{"token": &types.AttributeValueMemberS{Value: token}},
		UpdateExpression:    aws.String("SET #s = :revoked"),
		ConditionExpression: aws.String("#s = :pending"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":revoked": &types.AttributeValueMemberS{Value: string(domain.InviteRevoked)},
			":pending": &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
		},
	})
	if err != nil {
		var ccf *types.ConditionalCheckFailedException
		if errors.As(err, &ccf) {
			return ErrNotFound
		}
		return err
	}
	return nil
}
```

Note: add `"errors"` to the import block for `Revoke`.

- [ ] **Step 8.4: Add `AcceptInvitation` to `store/transactions.go`**

Append to `shared/go-common/store/transactions.go`:

```go
// AcceptInvitation atomically flips a pending invitation to accepted and writes
// the membership. The pending condition makes concurrent accepts safe: exactly
// one transaction wins.
func (s *Stores) AcceptInvitation(ctx context.Context, token string, m domain.Membership) error {
	mi, err := attributevalue.MarshalMap(m)
	if err != nil {
		return err
	}
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{Update: &types.Update{
				TableName:           aws.String(s.names.Invitations),
				Key:                 map[string]types.AttributeValue{"token": &types.AttributeValueMemberS{Value: token}},
				UpdateExpression:    aws.String("SET #s = :accepted"),
				ConditionExpression: aws.String("#s = :pending"),
				ExpressionAttributeNames: map[string]string{"#s": "status"},
				ExpressionAttributeValues: map[string]types.AttributeValue{
					":accepted": &types.AttributeValueMemberS{Value: string(domain.InviteAccepted)},
					":pending":  &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
				},
			}},
			{Put: &types.Put{TableName: aws.String(s.names.Memberships), Item: mi}},
		},
	})
	return err
}
```

- [ ] **Step 8.5: Run, expect PASS**

Run: `cd shared/go-common && go test ./store/ -run TestInvitation`
Expected: PASS.

- [ ] **Step 8.6: Run the whole store + domain suite**

Run: `cd shared/go-common && go test ./...`
Expected: PASS.

- [ ] **Step 8.7: Commit**

```bash
git add shared/go-common/store/invitation.go shared/go-common/store/transactions.go shared/go-common/store/invitation_test.go
git commit -m "feat(store): InvitationStore and atomic accept transaction"
```

**Acceptance Criteria — Task 8:**

- Create → `ListPendingByEmail` returns it; accept writes the membership and flips status atomically; a second accept fails the pending condition (concurrency-safe).
- `Revoke` returns `ErrNotFound` when the invite isn't pending.
- `go test ./...` passes in `shared/go-common`.

---

## Section 3 — Authorization primitive & auth middleware

### Task 9: `auth` package + API response/permission helpers

> The reusable primitive is the `AuthContext` + its predicates (kept HTTP-free in `go-common` so
> B3/B2 can reuse it); the thin 403-writing wrappers live in the `api` layer.

**Files:**

- Create: `shared/go-common/auth/context.go`
- Test: `shared/go-common/auth/context_test.go`
- Create: `api/internal/httpx/httpx.go`

- [ ] **Step 9.1: Write the failing test for the predicates**

Create `shared/go-common/auth/context_test.go`:

```go
package auth

import (
	"context"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func ctxWith() *AuthContext {
	return &AuthContext{
		UserID: "u1", Email: "u1@x.com",
		Memberships: map[string]domain.Role{"g1": domain.RoleAdmin, "g2": domain.RoleCaregiver},
	}
}

func TestPredicates(t *testing.T) {
	a := ctxWith()
	if !a.IsMember("g1") || !a.IsMember("g2") || a.IsMember("g3") {
		t.Fatal("IsMember")
	}
	if !a.IsAdmin("g1") || a.IsAdmin("g2") || a.IsAdmin("g3") {
		t.Fatal("IsAdmin")
	}
	if r, ok := a.RoleIn("g2"); !ok || r != domain.RoleCaregiver {
		t.Fatalf("RoleIn g2: %v %v", r, ok)
	}
}

func TestContextRoundTrip(t *testing.T) {
	a := ctxWith()
	ctx := NewContext(context.Background(), a)
	if FromContext(ctx) != a {
		t.Fatal("round trip")
	}
	if FromContext(context.Background()) != nil {
		t.Fatal("absent should be nil")
	}
}
```

- [ ] **Step 9.2: Run, expect FAIL**

Run: `cd shared/go-common && go test ./auth/...`
Expected: FAIL — undefined `AuthContext`.

- [ ] **Step 9.3: Implement `auth/context.go`**

Create `shared/go-common/auth/context.go`:

```go
// Package auth holds the authenticated caller's identity + authorization state.
// It is HTTP-free so every backend phase can reuse it.
package auth

import (
	"context"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

// AuthContext is the caller's identity plus their care-group memberships.
type AuthContext struct {
	UserID      string
	Email       string
	Memberships map[string]domain.Role // care_group_id -> role
}

func (a AuthContext) RoleIn(careGroupID string) (domain.Role, bool) {
	r, ok := a.Memberships[careGroupID]
	return r, ok
}

func (a AuthContext) IsMember(careGroupID string) bool {
	_, ok := a.Memberships[careGroupID]
	return ok
}

func (a AuthContext) IsAdmin(careGroupID string) bool {
	r, ok := a.Memberships[careGroupID]
	return ok && r == domain.RoleAdmin
}

type ctxKey struct{}

func NewContext(ctx context.Context, a *AuthContext) context.Context {
	return context.WithValue(ctx, ctxKey{}, a)
}

func FromContext(ctx context.Context) *AuthContext {
	a, _ := ctx.Value(ctxKey{}).(*AuthContext)
	return a
}
```

- [ ] **Step 9.4: Run, expect PASS**

Run: `cd shared/go-common && go test ./auth/...`
Expected: PASS.

- [ ] **Step 9.5: Implement `api/internal/httpx/httpx.go`**

Create `api/internal/httpx/httpx.go`:

```go
// Package httpx holds shared HTTP response + permission helpers for handlers.
package httpx

import (
	"encoding/json"
	"net/http"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
)

func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

type errorBody struct {
	Message string `json:"message"`
}

func WriteError(w http.ResponseWriter, status int, msg string) {
	WriteJSON(w, status, errorBody{Message: msg})
}

// RequireMember writes 403 and returns false unless the caller is a member.
func RequireMember(w http.ResponseWriter, a *auth.AuthContext, careGroupID string) bool {
	if a == nil || !a.IsMember(careGroupID) {
		WriteError(w, http.StatusForbidden, "forbidden")
		return false
	}
	return true
}

// RequireAdmin writes 403 and returns false unless the caller is an admin.
func RequireAdmin(w http.ResponseWriter, a *auth.AuthContext, careGroupID string) bool {
	if a == nil || !a.IsAdmin(careGroupID) {
		WriteError(w, http.StatusForbidden, "forbidden")
		return false
	}
	return true
}
```

- [ ] **Step 9.6: Verify api compiles**

Run: `cd api && go build ./...`
Expected: builds.

- [ ] **Step 9.7: Commit**

```bash
git add shared/go-common/auth api/internal/httpx
git commit -m "feat(auth): AuthContext predicates and HTTP permission helpers"
```

**Acceptance Criteria — Task 9:**

- `go test ./auth/...` passes; `IsMember`/`IsAdmin`/`RoleIn` and the context round-trip behave as tested.
- `auth` imports no `net/http` (`go list -deps ./auth | grep net/http` is empty).
- `httpx.RequireMember`/`RequireAdmin` write a JSON `{"message":...}` 403 and return `false` for non-members/non-admins.

---

### Task 10: Auth middleware (JIT provisioning + membership load)

**Files:**

- Create: `api/internal/middleware/auth.go`
- Test: `api/internal/middleware/auth_test.go`

- [ ] **Step 10.1: Implement `api/internal/middleware/auth.go`**

> The claims extractor is an injectable field so the middleware is testable without the
> API Gateway plumbing. `claimsFromRequest` reads the **verified** claims the JWT authorizer
> placed in the APIGW v2 request context.
>
> **VERIFY at execution time:** `core.GetAPIGatewayV2ContextFromContext` and the
> `events.APIGatewayV2HTTPRequestContext.Authorizer.JWT.Claims` shape against the installed
> versions of `aws-lambda-go-api-proxy` and `aws-lambda-go` (both already in `api/go.mod`).

Create `api/internal/middleware/auth.go`:

```go
package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/awslabs/aws-lambda-go-api-proxy/core"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type claims struct {
	Sub, Email, Name string
}

// Authenticator builds the AuthContext per request: verified claims → JIT user
// provisioning → membership load → AuthContext attached to the request context.
type Authenticator struct {
	stores  *store.Stores
	now     func() time.Time
	extract func(*http.Request) (claims, bool)
}

func NewAuthenticator(s *store.Stores) *Authenticator {
	return &Authenticator{stores: s, now: time.Now, extract: claimsFromRequest}
}

func (m *Authenticator) Wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, ok := m.extract(r)
		if !ok || c.Sub == "" {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		ctx := r.Context()
		email := domain.NormalizeEmail(c.Email)

		if _, err := m.stores.Users.CreateIfAbsent(ctx, domain.User{
			UserID: c.Sub, Email: email, Name: c.Name, CreatedAt: m.now().UTC(),
		}); err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, "provisioning failed")
			return
		}

		ms, err := m.stores.Memberships.ListByUser(ctx, c.Sub)
		if err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, "auth load failed")
			return
		}
		ac := &auth.AuthContext{UserID: c.Sub, Email: email, Memberships: make(map[string]domain.Role, len(ms))}
		for _, mem := range ms {
			ac.Memberships[mem.CareGroupID] = mem.Role
		}
		next.ServeHTTP(w, r.WithContext(auth.NewContext(ctx, ac)))
	})
}

func claimsFromRequest(r *http.Request) (claims, bool) {
	reqCtx, ok := core.GetAPIGatewayV2ContextFromContext(r.Context())
	if !ok || reqCtx.Authorizer == nil || reqCtx.Authorizer.JWT == nil {
		return claims{}, false
	}
	cl := reqCtx.Authorizer.JWT.Claims
	return claims{Sub: cl["sub"], Email: cl["email"], Name: claimName(cl)}, true
}

func claimName(cl map[string]string) string {
	if n := cl["name"]; n != "" {
		return n
	}
	gn, fn := cl["given_name"], cl["family_name"]
	return strings.TrimSpace(gn + " " + fn)
}
```

- [ ] **Step 10.2: Write the middleware test (against DynamoDB Local)**

Create `api/internal/middleware/auth_test.go`:

```go
package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestAuthenticator_JITProvisionsAndAttachesContext(t *testing.T) {
	stores := dynamotest.Start(t)
	a := NewAuthenticator(stores)
	a.extract = func(r *http.Request) (claims, bool) {
		return claims{Sub: "sub-1", Email: "New@X.com", Name: "New"}, true
	}

	var seen *auth.AuthContext
	h := a.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = auth.FromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	// First request provisions the user.
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/me", nil))
	if rec.Code != http.StatusOK || seen == nil || seen.UserID != "sub-1" {
		t.Fatalf("first: code=%d ctx=%+v", rec.Code, seen)
	}
	if seen.Email != "new@x.com" {
		t.Fatalf("email should be normalized, got %q", seen.Email)
	}
	if u, err := stores.Users.Get(rec.Context(), "sub-1"); err != nil || u.Name != "New" {
		t.Fatalf("user not provisioned: %+v err=%v", u, err)
	}

	// Second request is a no-op create; still succeeds.
	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, httptest.NewRequest(http.MethodGet, "/me", nil))
	if rec2.Code != http.StatusOK {
		t.Fatalf("second: code=%d", rec2.Code)
	}
}

func TestAuthenticator_MissingClaims401(t *testing.T) {
	stores := dynamotest.Start(t)
	a := NewAuthenticator(stores)
	a.extract = func(r *http.Request) (claims, bool) { return claims{}, false }
	h := a.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/me", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
}
```

Note: `rec.Context()` isn't a thing — use `context.Background()` for the `stores.Users.Get` call. Adjust the test to `import "context"` and call `stores.Users.Get(context.Background(), "sub-1")`.

- [ ] **Step 10.3: Run, expect PASS**

Run: `cd api && go test ./internal/middleware/...`
Expected: PASS (JIT provisions, normalizes email, attaches context; missing claims → 401).

- [ ] **Step 10.4: Commit**

```bash
git add api/internal/middleware
git commit -m "feat(api): JIT auth middleware building AuthContext from JWT claims"
```

**Acceptance Criteria — Task 10:**

- First request through `Wrap` creates the `user` row and attaches an `AuthContext` with the normalized email; a second request still succeeds (idempotent).
- Missing/empty `sub` → 401 and the inner handler never runs.
- The claims extractor is injectable (the test overrides it without API Gateway plumbing).

---

## Section 4 — Handlers & the isolation suite

> Handler tests attach an `AuthContext` directly via `auth.NewContext` (no middleware needed) and run
> against DynamoDB Local. A shared `withAuth` helper keeps them DRY.

### Task 11: `GET /me`

**Files:**

- Create: `api/internal/handlers/testhelpers_test.go`
- Create: `api/internal/handlers/me.go`
- Test: `api/internal/handlers/me_test.go`

- [ ] **Step 11.1: Shared test helper**

Create `api/internal/handlers/testhelpers_test.go`:

```go
package handlers_test

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func withAuth(r *http.Request, userID, email string, memberships map[string]domain.Role) *http.Request {
	if memberships == nil {
		memberships = map[string]domain.Role{}
	}
	ac := &auth.AuthContext{UserID: userID, Email: email, Memberships: memberships}
	return r.WithContext(auth.NewContext(r.Context(), ac))
}
```

- [ ] **Step 11.2: Write the failing test**

Create `api/internal/handlers/me_test.go`:

```go
package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestMe_returnsUserAndMemberships(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	_, _ = s.Users.CreateIfAbsent(ctx, domain.User{UserID: "u1", Email: "u1@x.com", Name: "U1", CreatedAt: now})
	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "Group One", CreatedBy: "u1", CreatedAt: now},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})

	h := handlers.NewMe(s)
	req := withAuth(httptest.NewRequest(http.MethodGet, "/me", nil), "u1", "u1@x.com",
		map[string]domain.Role{"g1": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	var body struct {
		User        struct{ UserID, Email, Name string } `json:"user"`
		Memberships []struct {
			CareGroupID string `json:"care_group_id"`
			Name        string `json:"name"`
			Role        string `json:"role"`
		} `json:"memberships"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.User.UserID != "u1" || len(body.Memberships) != 1 ||
		body.Memberships[0].Name != "Group One" || body.Memberships[0].Role != "admin" {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}
```

- [ ] **Step 11.3: Implement `me.go`**

Create `api/internal/handlers/me.go`:

```go
package handlers

import (
	"net/http"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Me struct{ stores *store.Stores }

func NewMe(s *store.Stores) *Me { return &Me{stores: s} }

type meUser struct {
	UserID    string `json:"user_id"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	CreatedAt string `json:"created_at"`
}
type meMembership struct {
	CareGroupID string `json:"care_group_id"`
	Name        string `json:"name"`
	Role        string `json:"role"`
}
type meResponse struct {
	User        meUser         `json:"user"`
	Memberships []meMembership `json:"memberships"`
}

func (h *Me) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	u, err := h.stores.Users.Get(ctx, ac.UserID)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "user load failed")
		return
	}
	ids := make([]string, 0, len(ac.Memberships))
	for id := range ac.Memberships {
		ids = append(ids, id)
	}
	groups, err := h.stores.CareGroups.BatchGet(ctx, ids)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "group load failed")
		return
	}
	resp := meResponse{
		User:        meUser{UserID: u.UserID, Email: u.Email, Name: u.Name, CreatedAt: u.CreatedAt.UTC().Format(time.RFC3339)},
		Memberships: make([]meMembership, 0, len(ac.Memberships)),
	}
	for id, role := range ac.Memberships {
		resp.Memberships = append(resp.Memberships, meMembership{CareGroupID: id, Name: groups[id].Name, Role: string(role)})
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}
```

- [ ] **Step 11.4: Run, expect PASS**

Run: `cd api && go test ./internal/handlers/ -run TestMe`
Expected: PASS.

- [ ] **Step 11.5: Commit**

```bash
git add api/internal/handlers/me.go api/internal/handlers/me_test.go api/internal/handlers/testhelpers_test.go
git commit -m "feat(api): GET /me handler"
```

**Acceptance Criteria — Task 11:**

- `GET /me` returns the caller's `user` plus a `memberships` array with resolved group `name` and `role`.
- No `AuthContext` → 401.

---

### Task 12: `POST /care-groups`, invitations create + revoke

**Files:**

- Modify: `shared/go-common/store/user.go` (add `GetByEmail`)
- Test: `shared/go-common/store/user_test.go` (extend)
- Create: `api/internal/handlers/caregroups.go`
- Test: `api/internal/handlers/caregroups_test.go`
- Modify: `api/go.mod` (add `github.com/google/uuid`)

- [ ] **Step 12.1: Add `UserStore.GetByEmail` (needed for the already-a-member check)**

Append to `shared/go-common/store/user.go`:

```go
// GetByEmail looks up a user via the email-index. Returns ErrNotFound if none.
func (s *UserStore) GetByEmail(ctx context.Context, email string) (domain.User, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(emailIndex),
		KeyConditionExpression: aws.String("email = :e"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":e": &types.AttributeValueMemberS{Value: email},
		},
		Limit: aws.Int32(1),
	})
	if err != nil {
		return domain.User{}, err
	}
	if len(out.Items) == 0 {
		return domain.User{}, ErrNotFound
	}
	var u domain.User
	if err := attributevalue.UnmarshalMap(out.Items[0], &u); err != nil {
		return domain.User{}, err
	}
	return u, nil
}
```

Extend `shared/go-common/store/user_test.go` with:

```go
func TestUserStore_GetByEmail(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	_, _ = s.Users.CreateIfAbsent(ctx, domain.User{UserID: "sub-1", Email: "a@b.com", Name: "A", CreatedAt: time.Now().UTC()})
	u, err := s.Users.GetByEmail(ctx, "a@b.com")
	if err != nil || u.UserID != "sub-1" {
		t.Fatalf("GetByEmail: %+v err=%v", u, err)
	}
	if _, err := s.Users.GetByEmail(ctx, "none@x.com"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}
```

Run: `cd shared/go-common && go test ./store/ -run TestUserStore` → Expected: PASS.

- [ ] **Step 12.2: Add the uuid dependency**

```bash
cd api && go get github.com/google/uuid@latest
```

- [ ] **Step 12.3: Write the failing handler test**

Create `api/internal/handlers/caregroups_test.go`:

```go
package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestCareGroups_createMakesAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)

	req := withAuth(httptest.NewRequest(http.MethodPost, "/care-groups", strings.NewReader(`{"name":"Mom"}`)), "u1", "u1@x.com", nil)
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	var body struct {
		CareGroupID string `json:"care_group_id"`
		Name        string `json:"name"`
		Role        string `json:"role"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Role != "admin" || body.Name != "Mom" || body.CareGroupID == "" {
		t.Fatalf("unexpected: %s", rec.Body.String())
	}
	if m, err := s.Memberships.Get(context.Background(), "u1", body.CareGroupID); err != nil || m.Role != domain.RoleAdmin {
		t.Fatalf("admin membership not created: %+v err=%v", m, err)
	}
}

func TestCareGroups_createRejectsEmptyName(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)
	req := withAuth(httptest.NewRequest(http.MethodPost, "/care-groups", strings.NewReader(`{"name":"  "}`)), "u1", "u1@x.com", nil)
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestCareGroups_inviteRequiresAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)

	// caregiver (not admin) of g1 tries to invite → 403
	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"x@y.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u2", "u2@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.CreateInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d", rec.Code)
	}
}

func TestCareGroups_inviteSucceedsForAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewCareGroups(s)
	_ = s.CreateCareGroupWithAdmin(context.Background(),
		domain.CareGroup{CareGroupID: "g1", Name: "G", CreatedBy: "u1", CreatedAt: time.Now().UTC()},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: time.Now().UTC()})

	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"Invitee@X.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.CreateInvitation(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("code=%d body=%s", rec.Code, rec.Body.String())
	}
	var body struct {
		Token     string `json:"token"`
		Email     string `json:"email"`
		Role      string `json:"role"`
		ExpiresAt string `json:"expires_at"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Token == "" || body.Email != "invitee@x.com" || body.Role != "caregiver" {
		t.Fatalf("unexpected invite: %s", rec.Body.String())
	}
}
```

- [ ] **Step 12.4: Implement `caregroups.go`**

Create `api/internal/handlers/caregroups.go`:

```go
package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type CareGroups struct {
	stores    *store.Stores
	now       func() time.Time
	newID     func() string
	newToken  func() (string, error)
	inviteTTL time.Duration
}

func NewCareGroups(s *store.Stores) *CareGroups {
	return &CareGroups{
		stores:    s,
		now:       time.Now,
		newID:     uuid.NewString,
		newToken:  domain.NewInviteToken,
		inviteTTL: 14 * 24 * time.Hour,
	}
}

func (h *CareGroups) Create(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		httpx.WriteError(w, http.StatusBadRequest, "name is required")
		return
	}
	now := h.now().UTC()
	g := domain.CareGroup{CareGroupID: h.newID(), Name: strings.TrimSpace(req.Name), CreatedBy: ac.UserID, CreatedAt: now}
	m := domain.Membership{UserID: ac.UserID, CareGroupID: g.CareGroupID, Role: domain.RoleAdmin, CreatedAt: now}
	if err := h.stores.CreateCareGroupWithAdmin(r.Context(), g, m); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, map[string]any{
		"care_group_id": g.CareGroupID, "name": g.Name, "role": string(domain.RoleAdmin),
	})
}

func (h *CareGroups) CreateInvitation(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	groupID := r.PathValue("careGroupId")
	if !httpx.RequireAdmin(w, ac, groupID) {
		return
	}
	var req struct {
		Email string      `json:"email"`
		Role  domain.Role `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	email := domain.NormalizeEmail(req.Email)
	if email == "" || !req.Role.Valid() {
		httpx.WriteError(w, http.StatusBadRequest, "email and a valid role are required")
		return
	}
	ctx := r.Context()

	// Reject a duplicate pending invite for the same group.
	pending, err := h.stores.Invitations.ListPendingByEmail(ctx, email)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return
	}
	for _, p := range pending {
		if p.CareGroupID == groupID {
			httpx.WriteError(w, http.StatusConflict, "an invite is already pending for this email")
			return
		}
	}
	// Reject if the email already belongs to a member.
	if u, err := h.stores.Users.GetByEmail(ctx, email); err == nil {
		if _, err := h.stores.Memberships.Get(ctx, u.UserID, groupID); err == nil {
			httpx.WriteError(w, http.StatusConflict, "already a member")
			return
		}
	}

	token, err := h.newToken()
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "token generation failed")
		return
	}
	expiresAt := h.now().Add(h.inviteTTL).UTC()
	inv := domain.Invitation{
		Token: token, CareGroupID: groupID, Email: email, Role: req.Role,
		Status: domain.InvitePending, InvitedBy: ac.UserID, CreatedAt: h.now().UTC(), ExpiresAt: expiresAt.Unix(),
	}
	if err := h.stores.Invitations.Create(ctx, inv); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "create invite failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, map[string]any{
		"token": token, "email": email, "role": string(req.Role),
		"expires_at": expiresAt.Format(time.RFC3339),
	})
}

func (h *CareGroups) RevokeInvitation(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	groupID := r.PathValue("careGroupId")
	if !httpx.RequireAdmin(w, ac, groupID) {
		return
	}
	token := r.PathValue("token")
	inv, err := h.stores.Invitations.Get(r.Context(), token)
	if err != nil || inv.CareGroupID != groupID {
		httpx.WriteError(w, http.StatusNotFound, "invitation not found")
		return
	}
	if err := h.stores.Invitations.Revoke(r.Context(), token); err != nil {
		httpx.WriteError(w, http.StatusNotFound, "invitation not pending")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 12.5: Run, expect PASS**

Run: `cd api && go test ./internal/handlers/ -run TestCareGroups`
Expected: PASS.

- [ ] **Step 12.6: Commit**

```bash
git add shared/go-common/store/user.go shared/go-common/store/user_test.go api/internal/handlers/caregroups.go api/internal/handlers/caregroups_test.go api/go.mod api/go.sum
git commit -m "feat(api): create care group and invitation create/revoke"
```

**Acceptance Criteria — Task 12:**

- `Create` makes the caller Admin (group + membership exist); empty name → 400.
- `CreateInvitation` → 403 for a non-admin; 201 with a token + normalized email for an admin; duplicate pending invite or existing member → 409.
- `RevokeInvitation` → 204 for a pending invite in the group; 404 otherwise.

---

### Task 13: `GET /invitations/mine` + `POST /invitations/{token}/accept`

**Files:**

- Create: `api/internal/handlers/invitations.go`
- Test: `api/internal/handlers/invitations_test.go`

- [ ] **Step 13.1: Write the failing test**

Create `api/internal/handlers/invitations_test.go`:

```go
package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestInvitations_mineAndAccept(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()

	// group + admin, then an invite for invitee@x.com
	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "Group", CreatedBy: "u1", CreatedAt: now},
		domain.Membership{UserID: "u1", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "tok-1", CareGroupID: "g1", Email: "invitee@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	})

	mine := handlers.NewInvitations(s)
	// discovery by verified email
	req := withAuth(httptest.NewRequest(http.MethodGet, "/invitations/mine", nil), "u2", "invitee@x.com", nil)
	rec := httptest.NewRecorder()
	mine.Mine(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("mine code=%d", rec.Code)
	}
	var list []struct {
		Token         string `json:"token"`
		CareGroupName string `json:"care_group_name"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &list)
	if len(list) != 1 || list[0].Token != "tok-1" || list[0].CareGroupName != "Group" {
		t.Fatalf("unexpected mine: %s", rec.Body.String())
	}

	// accept by token (not gated on email match)
	areq := httptest.NewRequest(http.MethodPost, "/invitations/tok-1/accept", nil)
	areq.SetPathValue("token", "tok-1")
	areq = withAuth(areq, "u2", "invitee@x.com", nil)
	arec := httptest.NewRecorder()
	mine.Accept(arec, areq)
	if arec.Code != http.StatusOK {
		t.Fatalf("accept code=%d body=%s", arec.Code, arec.Body.String())
	}
	if m, err := s.Memberships.Get(ctx, "u2", "g1"); err != nil || m.Role != domain.RoleCaregiver {
		t.Fatalf("membership not created: %+v err=%v", m, err)
	}

	// idempotent re-accept
	arec2 := httptest.NewRecorder()
	areq2 := httptest.NewRequest(http.MethodPost, "/invitations/tok-1/accept", nil)
	areq2.SetPathValue("token", "tok-1")
	areq2 = withAuth(areq2, "u2", "invitee@x.com", nil)
	mine.Accept(arec2, areq2)
	if arec2.Code != http.StatusOK {
		t.Fatalf("re-accept should be idempotent, got %d", arec2.Code)
	}
}

func TestInvitations_acceptExpired410(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	past := time.Now().Add(-time.Hour).UTC()
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "old", CareGroupID: "g1", Email: "x@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "u1", CreatedAt: past, ExpiresAt: past.Unix(),
	})
	h := handlers.NewInvitations(s)
	req := httptest.NewRequest(http.MethodPost, "/invitations/old/accept", nil)
	req.SetPathValue("token", "old")
	req = withAuth(req, "u2", "x@x.com", nil)
	rec := httptest.NewRecorder()
	h.Accept(rec, req)
	if rec.Code != http.StatusGone {
		t.Fatalf("want 410, got %d", rec.Code)
	}
}
```

- [ ] **Step 13.2: Implement `invitations.go`**

Create `api/internal/handlers/invitations.go`:

```go
package handlers

import (
	"net/http"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Invitations struct {
	stores *store.Stores
	now    func() time.Time
}

func NewInvitations(s *store.Stores) *Invitations {
	return &Invitations{stores: s, now: time.Now}
}

type pendingInvitation struct {
	Token         string `json:"token"`
	CareGroupID   string `json:"care_group_id"`
	CareGroupName string `json:"care_group_name"`
	Role          string `json:"role"`
	InvitedBy     string `json:"invited_by"`
}

func (h *Invitations) Mine(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	invs, err := h.stores.Invitations.ListPendingByEmail(ctx, ac.Email)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return
	}
	ids := make([]string, 0, len(invs))
	for _, in := range invs {
		ids = append(ids, in.CareGroupID)
	}
	groups, err := h.stores.CareGroups.BatchGet(ctx, ids)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "group load failed")
		return
	}
	out := make([]pendingInvitation, 0, len(invs))
	for _, in := range invs {
		out = append(out, pendingInvitation{
			Token: in.Token, CareGroupID: in.CareGroupID, CareGroupName: groups[in.CareGroupID].Name,
			Role: string(in.Role), InvitedBy: in.InvitedBy,
		})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Invitations) Accept(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	token := r.PathValue("token")

	inv, err := h.stores.Invitations.Get(ctx, token)
	if err != nil {
		httpx.WriteError(w, http.StatusNotFound, "invitation not found")
		return
	}
	// Idempotent: already accepted and the caller is already a member.
	if inv.Status == domain.InviteAccepted {
		if _, err := h.stores.Memberships.Get(ctx, ac.UserID, inv.CareGroupID); err == nil {
			h.respondAccepted(w, inv)
			return
		}
	}
	if inv.Status != domain.InvitePending {
		httpx.WriteError(w, http.StatusGone, "invitation no longer valid")
		return
	}
	if inv.Expired(h.now()) {
		httpx.WriteError(w, http.StatusGone, "invitation expired")
		return
	}

	mem := domain.Membership{UserID: ac.UserID, CareGroupID: inv.CareGroupID, Role: inv.Role, CreatedAt: h.now().UTC()}
	if err := h.stores.AcceptInvitation(ctx, token, mem); err != nil {
		// Lost a race (already accepted) — idempotent if the membership now exists.
		if _, gErr := h.stores.Memberships.Get(ctx, ac.UserID, inv.CareGroupID); gErr == nil {
			h.respondAccepted(w, inv)
			return
		}
		httpx.WriteError(w, http.StatusGone, "invitation no longer valid")
		return
	}
	h.respondAccepted(w, inv)
}

func (h *Invitations) respondAccepted(w http.ResponseWriter, inv domain.Invitation) {
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"care_group_id": inv.CareGroupID, "role": string(inv.Role),
	})
}
```

- [ ] **Step 13.3: Run, expect PASS**

Run: `cd api && go test ./internal/handlers/ -run TestInvitations`
Expected: PASS (discovery by email; token-first accept; idempotent; expired → 410).

- [ ] **Step 13.4: Commit**

```bash
git add api/internal/handlers/invitations.go api/internal/handlers/invitations_test.go
git commit -m "feat(api): list-my-invitations and token-first accept"
```

**Acceptance Criteria — Task 13:**

- `Mine` returns pending invites matched by the caller's verified email, with resolved group names.
- `Accept` is token-first (not gated on email match), creates the membership, is idempotent on re-accept, and returns 410 for expired/non-pending tokens, 404 for unknown tokens.

---

### Task 14: Cross-tenant isolation suite (security gate)

**Files:**

- Create: `api/internal/handlers/isolation_test.go`

- [ ] **Step 14.1: Write the isolation suite**

Create `api/internal/handlers/isolation_test.go`:

```go
package handlers_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

// Isolation: a user who is admin of their own group must not touch another group.

func TestIsolation_nonMemberCannotInvite(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()
	_ = s.CreateCareGroupWithAdmin(ctx,
		domain.CareGroup{CareGroupID: "g1", Name: "A", CreatedBy: "userA", CreatedAt: now},
		domain.Membership{UserID: "userA", CareGroupID: "g1", Role: domain.RoleAdmin, CreatedAt: now})

	cg := handlers.NewCareGroups(s)
	// userB is admin of their OWN group g2, but a stranger to g1.
	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"z@z.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "userB", "userB@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	cg.CreateInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("stranger invite should be 403, got %d", rec.Code)
	}
}

func TestIsolation_zeroMembershipSeesNothing(t *testing.T) {
	s := dynamotest.Start(t)
	_, _ = s.Users.CreateIfAbsent(context.Background(), domain.User{UserID: "lonely", Email: "l@x.com", Name: "L", CreatedAt: time.Now().UTC()})
	me := handlers.NewMe(s)
	req := withAuth(httptest.NewRequest(http.MethodGet, "/me", nil), "lonely", "l@x.com", nil)
	rec := httptest.NewRecorder()
	me.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"memberships":[]`) {
		t.Fatalf("zero-membership user should see empty memberships: %s", rec.Body.String())
	}
}

func TestIsolation_caregiverCannotInvite(t *testing.T) {
	s := dynamotest.Start(t)
	cg := handlers.NewCareGroups(s)
	// caregiver (not admin) of g1
	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/invitations", strings.NewReader(`{"email":"z@z.com","role":"caregiver"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u3", "u3@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	cg.CreateInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver invite should be 403, got %d", rec.Code)
	}
}

func TestIsolation_strangerCannotRevoke(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()
	_ = s.Invitations.Create(ctx, domain.Invitation{
		Token: "tokA", CareGroupID: "g1", Email: "p@x.com", Role: domain.RoleCaregiver,
		Status: domain.InvitePending, InvitedBy: "userA", CreatedAt: now, ExpiresAt: now.Add(time.Hour).Unix(),
	})
	cg := handlers.NewCareGroups(s)
	req := httptest.NewRequest(http.MethodDelete, "/care-groups/g1/invitations/tokA", nil)
	req.SetPathValue("careGroupId", "g1")
	req.SetPathValue("token", "tokA")
	req = withAuth(req, "userB", "userB@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	cg.RevokeInvitation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("stranger revoke should be 403, got %d", rec.Code)
	}
	// invite must still be pending
	if inv, _ := s.Invitations.Get(ctx, "tokA"); inv.Status != domain.InvitePending {
		t.Fatalf("invite should remain pending, got %s", inv.Status)
	}
}
```

(Delete the unused `setupTwoGroups` stub before running — it's illustrative scaffolding, not needed.)

- [ ] **Step 14.2: Run the full handler suite (the `setupTwoGroups` mention is gone — nothing to delete)**

Run: `cd api && go test ./internal/...`
Expected: PASS (all handler + middleware + isolation tests).

- [ ] **Step 14.3: Commit**

```bash
git add api/internal/handlers/isolation_test.go
git commit -m "test(api): cross-tenant isolation suite"
```

**Acceptance Criteria — Task 14:**

- A user who is admin of their _own_ group gets 403 inviting to / revoking in a group they don't belong to, and the target data is unchanged.
- A `caregiver` gets 403 on admin-only actions.
- A zero-membership user's `GET /me` returns an empty `memberships` array.

---

## Section 5 — Infrastructure (CDK)

### Task 15: DynamoDB tables in `SharedStack`

**Files:**

- Modify: `infra/lib/shared-stack.ts`
- Test: `infra/test/shared-stack.test.ts`

- [ ] **Step 15.1: Write the failing test (table assertions)**

Add to `infra/test/shared-stack.test.ts`:

```ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { SharedStack } from '../lib/shared-stack';

test('shared stack creates the four B1 tables with prefixed names', () => {
  const app = new cdk.App();
  const stack = new SharedStack(app, 'CaregiverDev-Shared', {
    env: { account: '123456789012', region: 'us-east-2' },
    stage: 'dev',
  });
  const t = Template.fromStack(stack);
  t.resourceCountIs('AWS::DynamoDB::Table', 4);
  for (const name of [
    'caregiver-dev-user',
    'caregiver-dev-care-group',
    'caregiver-dev-membership',
    'caregiver-dev-invitation',
  ]) {
    t.hasResourceProperties('AWS::DynamoDB::Table', { TableName: name });
  }
});

test('invitation table has a TTL on expires_at', () => {
  const app = new cdk.App();
  const stack = new SharedStack(app, 'CaregiverDev-Shared', {
    env: { account: '123456789012', region: 'us-east-2' },
    stage: 'dev',
  });
  Template.fromStack(stack).hasResourceProperties('AWS::DynamoDB::Table', {
    TableName: 'caregiver-dev-invitation',
    TimeToLiveSpecification: { AttributeName: 'expires_at', Enabled: true },
  });
});
```

- [ ] **Step 15.2: Run, expect FAIL**

Run: `cd infra && pnpm test -- shared-stack`
Expected: FAIL (0 tables found).

- [ ] **Step 15.3: Add the tables to `shared-stack.ts`**

Add the import at the top of `infra/lib/shared-stack.ts`:

```ts
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
```

Add these public fields to the `SharedStack` class (next to the existing ones):

```ts
  public readonly tables: {
    users: dynamodb.Table;
    careGroups: dynamodb.Table;
    memberships: dynamodb.Table;
    invitations: dynamodb.Table;
  };
```

Inside the constructor (after the alarm topic, before/after AppConfig — order doesn't matter), add:

```ts
const removalPolicy = props.stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY;
const tableBase = {
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  removalPolicy,
  // If the installed CDK flags `pointInTimeRecovery` as deprecated, switch to
  // `pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: props.stage === 'prod' }`.
  pointInTimeRecovery: props.stage === 'prod',
};
const s = dynamodb.AttributeType.STRING;

const users = new dynamodb.Table(this, 'UsersTable', {
  ...tableBase,
  tableName: `caregiver-${props.stage}-user`,
  partitionKey: { name: 'user_id', type: s },
});
users.addGlobalSecondaryIndex({
  indexName: 'email-index',
  partitionKey: { name: 'email', type: s },
});

const careGroups = new dynamodb.Table(this, 'CareGroupsTable', {
  ...tableBase,
  tableName: `caregiver-${props.stage}-care-group`,
  partitionKey: { name: 'care_group_id', type: s },
});

const memberships = new dynamodb.Table(this, 'MembershipsTable', {
  ...tableBase,
  tableName: `caregiver-${props.stage}-membership`,
  partitionKey: { name: 'user_id', type: s },
  sortKey: { name: 'care_group_id', type: s },
});
memberships.addGlobalSecondaryIndex({
  indexName: 'group-index',
  partitionKey: { name: 'care_group_id', type: s },
  sortKey: { name: 'user_id', type: s },
});

const invitations = new dynamodb.Table(this, 'InvitationsTable', {
  ...tableBase,
  tableName: `caregiver-${props.stage}-invitation`,
  partitionKey: { name: 'token', type: s },
  timeToLiveAttribute: 'expires_at',
});
invitations.addGlobalSecondaryIndex({
  indexName: 'group-index',
  partitionKey: { name: 'care_group_id', type: s },
});
invitations.addGlobalSecondaryIndex({
  indexName: 'email-index',
  partitionKey: { name: 'email', type: s },
});

this.tables = { users, careGroups, memberships, invitations };
```

- [ ] **Step 15.4: Run, expect PASS**

Run: `cd infra && pnpm test -- shared-stack`
Expected: PASS.

- [ ] **Step 15.5: Commit**

```bash
git add infra/lib/shared-stack.ts infra/test/shared-stack.test.ts
git commit -m "feat(infra): B1 DynamoDB tables in shared stack"
```

**Acceptance Criteria — Task 15:**

- `SharedStack` synthesizes exactly four DynamoDB tables with the `caregiver-{stage}-<entity>` names and the GSIs from spec §5.
- The invitation table has a TTL on `expires_at`; prod uses `RETAIN` + PITR (verify via `cdk synth --context stage=prod`).

---

### Task 16: Cognito user pool in `SharedStack`

**Files:**

- Modify: `infra/lib/shared-stack.ts`
- Test: `infra/test/shared-stack.test.ts`

- [ ] **Step 16.1: Write the failing test**

Add to `infra/test/shared-stack.test.ts`:

```ts
test('shared stack creates a Cognito user pool + app client', () => {
  const app = new cdk.App();
  const stack = new SharedStack(app, 'CaregiverDev-Shared', {
    env: { account: '123456789012', region: 'us-east-2' },
    stage: 'dev',
  });
  const t = Template.fromStack(stack);
  t.hasResourceProperties('AWS::Cognito::UserPool', { UserPoolName: 'caregiver-dev' });
  t.resourceCountIs('AWS::Cognito::UserPoolClient', 1);
});
```

- [ ] **Step 16.2: Run, expect FAIL**

Run: `cd infra && pnpm test -- shared-stack`
Expected: FAIL.

- [ ] **Step 16.3: Add Cognito to `shared-stack.ts`**

Add the import:

```ts
import * as cognito from 'aws-cdk-lib/aws-cognito';
```

Add public fields:

```ts
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
```

In the constructor:

```ts
this.userPool = new cognito.UserPool(this, 'UserPool', {
  userPoolName: `caregiver-${props.stage}`,
  selfSignUpEnabled: true,
  signInAliases: { email: true },
  autoVerify: { email: true },
  standardAttributes: {
    email: { required: true, mutable: true },
    fullname: { required: false, mutable: true },
  },
  passwordPolicy: { minLength: 8, requireLowercase: true, requireDigits: true },
  removalPolicy: props.stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
});

// Public client for the native iOS app (no secret). Federation (Sign in with
// Apple) is added when the C1 client design lands.
this.userPoolClient = this.userPool.addClient('AppClient', {
  userPoolClientName: `caregiver-${props.stage}-app`,
  // userSrp is what the iOS app uses; adminUserPassword lets the Task 19 smoke
  // (and server-side test sign-in) mint a token via the AWS CLI.
  authFlows: { userSrp: true, adminUserPassword: true },
  generateSecret: false,
});

new cdk.CfnOutput(this, 'UserPoolId', { value: this.userPool.userPoolId });
new cdk.CfnOutput(this, 'UserPoolClientId', { value: this.userPoolClient.userPoolClientId });
```

- [ ] **Step 16.4: Run, expect PASS**

Run: `cd infra && pnpm test -- shared-stack`
Expected: PASS.

- [ ] **Step 16.5: Commit**

```bash
git add infra/lib/shared-stack.ts infra/test/shared-stack.test.ts
git commit -m "feat(infra): Cognito user pool + app client in shared stack"
```

**Acceptance Criteria — Task 16:**

- `SharedStack` synthesizes a Cognito user pool named `caregiver-{stage}` with email sign-in/self-signup and one public app client (no secret).
- `userPool` and `userPoolClient` are exposed for `ApiStack`.

---

### Task 17: JWT authorizer, routes, and grants in `ApiStack`

**Files:**

- Modify: `infra/lib/api-stack.ts`
- Modify: `infra/bin/app.ts`
- Test: `infra/test/api-stack.test.ts`

- [ ] **Step 17.1: Extend `ApiStackProps` and wire from `bin/app.ts`**

In `infra/lib/api-stack.ts`, add imports:

```ts
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import { HttpUserPoolAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
```

Extend `ApiStackProps`:

```ts
userPool: cognito.IUserPool;
userPoolClient: cognito.IUserPoolClient;
tables: {
  users: dynamodb.ITable;
  careGroups: dynamodb.ITable;
  memberships: dynamodb.ITable;
  invitations: dynamodb.ITable;
}
```

In `infra/bin/app.ts`, pass them into the `ApiStack`:

```ts
const api = new ApiStack(app, `${prefix}-Api`, {
  env,
  stage,
  version,
  appConfigApplicationId: shared.appConfigApplicationId,
  appConfigEnvironmentId: shared.appConfigEnvironmentId,
  appConfigProfileId: shared.appConfigProfileId,
  userPool: shared.userPool,
  userPoolClient: shared.userPoolClient,
  tables: shared.tables,
});
```

- [ ] **Step 17.2: Grant table access + inject table-name env vars**

In `api-stack.ts`, after the `apiFunction` is created (and its AppConfig env vars set), add:

```ts
for (const table of Object.values(props.tables)) {
  table.grantReadWriteData(this.apiFunction);
}
this.apiFunction.addEnvironment('USERS_TABLE', props.tables.users.tableName);
this.apiFunction.addEnvironment('CARE_GROUPS_TABLE', props.tables.careGroups.tableName);
this.apiFunction.addEnvironment('MEMBERSHIPS_TABLE', props.tables.memberships.tableName);
this.apiFunction.addEnvironment('INVITATIONS_TABLE', props.tables.invitations.tableName);
```

- [ ] **Step 17.3: Add the JWT authorizer and the six routes**

Replace the current single-integration `addRoutes` calls’ surrounding area: keep `/health` and `/flags` unauthorized, and add the authorized routes. After the existing `/flags` route, add:

```ts
const authorizer = new HttpUserPoolAuthorizer('JwtAuthorizer', props.userPool, {
  userPoolClients: [props.userPoolClient],
});
const lambdaIntegration = new integ.HttpLambdaIntegration('ApiIntegration', this.apiFunction);

const authedRoutes: Array<{ path: string; methods: apigw.HttpMethod[] }> = [
  { path: '/me', methods: [apigw.HttpMethod.GET] },
  { path: '/care-groups', methods: [apigw.HttpMethod.POST] },
  { path: '/care-groups/{careGroupId}/invitations', methods: [apigw.HttpMethod.POST] },
  { path: '/care-groups/{careGroupId}/invitations/{token}', methods: [apigw.HttpMethod.DELETE] },
  { path: '/invitations/mine', methods: [apigw.HttpMethod.GET] },
  { path: '/invitations/{token}/accept', methods: [apigw.HttpMethod.POST] },
];
for (const route of authedRoutes) {
  httpApi.addRoutes({
    path: route.path,
    methods: route.methods,
    integration: lambdaIntegration,
    authorizer,
  });
}
```

- [ ] **Step 17.4: Write the failing test**

Add to `infra/test/api-stack.test.ts` (imports at top of the file if not already present:
`import { SharedStack } from '../lib/shared-stack';`). Construct a real `SharedStack` in the same
app so the wiring matches `bin/app.ts`:

```ts
test('api stack wires a JWT authorizer and authed routes', () => {
  const app = new cdk.App();
  const env = { account: '123456789012', region: 'us-east-2' };
  const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
  const apiStack = new ApiStack(app, 'CaregiverDev-Api', {
    env,
    stage: 'dev',
    version: '0.0.0',
    appConfigApplicationId: 'app',
    appConfigEnvironmentId: 'envid',
    appConfigProfileId: 'prof',
    userPool: shared.userPool,
    userPoolClient: shared.userPoolClient,
    tables: shared.tables,
  });
  const t = Template.fromStack(apiStack);
  t.resourceCountIs('AWS::ApiGatewayV2::Authorizer', 1);
  t.hasResourceProperties('AWS::ApiGatewayV2::Authorizer', { AuthorizerType: 'JWT' });
  // 2 unauthed (health, flags) + 6 authed routes = 8 routes
  t.resourceCountIs('AWS::ApiGatewayV2::Route', 8);
});
```

> Note: `ApiStack`'s constructor runs the Go cross-compile at synth time (as the existing
> `api-stack.test.ts` already does), so this test requires the Go toolchain and a compiling `api`
> module — which is exactly the integration we want covered.

- [ ] **Step 17.5: Run tests, expect PASS**

Run: `cd infra && pnpm test`
Expected: PASS (shared-stack + api-stack + existing guardrail tests).

- [ ] **Step 17.6: Synth both stages**

Run: `cd infra && pnpm exec cdk synth --context stage=dev && pnpm exec cdk synth --context stage=prod`
Expected: both synth without error; the stack-name guardrail passes.

- [ ] **Step 17.7: Commit**

```bash
git add infra/lib/api-stack.ts infra/bin/app.ts infra/test/api-stack.test.ts
git commit -m "feat(infra): JWT authorizer, B1 routes, and DynamoDB grants"
```

**Acceptance Criteria — Task 17:**

- `ApiStack` synthesizes one JWT authorizer and the six authed routes (health/flags stay unauthorized).
- The Lambda gets read/write grants on all four tables and the four `*_TABLE` env vars.
- `cdk synth` succeeds for both `dev` and `prod`.

---

## Section 6 — Wiring, deploy, and smoke

### Task 18: Wire the handlers + middleware into the Lambda mux

**Files:**

- Modify: `api/cmd/lambda/mux.go`
- Test: `api/cmd/lambda/mux_test.go`

- [ ] **Step 18.1: Replace `mux.go` with the wired version**

Replace `api/cmd/lambda/mux.go` with:

```go
package main

import (
	"context"
	"fmt"
	"net/http"
	"os"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/api/internal/middleware"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/flags"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

func newMux(cfg config.Config) (http.Handler, error) {
	mux := http.NewServeMux()
	mux.Handle("GET /health", handlers.NewHealth(cfg.Version, nil))

	appID := os.Getenv("APPCONFIG_APPLICATION_ID")
	envID := os.Getenv("APPCONFIG_ENVIRONMENT_ID")
	profileID := os.Getenv("APPCONFIG_PROFILE_ID")
	if appID == "" || envID == "" || profileID == "" {
		return nil, fmt.Errorf("APPCONFIG_APPLICATION_ID/ENVIRONMENT_ID/PROFILE_ID must all be set")
	}
	flagClient := flags.NewClientFromEnv(appID, envID, profileID)
	mux.Handle("GET /flags", handlers.NewFlags(flagClient, nil))

	stores, err := newStores(context.Background())
	if err != nil {
		return nil, err
	}
	authn := middleware.NewAuthenticator(stores)
	cg := handlers.NewCareGroups(stores)
	inv := handlers.NewInvitations(stores)

	mux.Handle("GET /me", authn.Wrap(handlers.NewMe(stores)))
	mux.Handle("POST /care-groups", authn.Wrap(http.HandlerFunc(cg.Create)))
	mux.Handle("POST /care-groups/{careGroupId}/invitations", authn.Wrap(http.HandlerFunc(cg.CreateInvitation)))
	mux.Handle("DELETE /care-groups/{careGroupId}/invitations/{token}", authn.Wrap(http.HandlerFunc(cg.RevokeInvitation)))
	mux.Handle("GET /invitations/mine", authn.Wrap(http.HandlerFunc(inv.Mine)))
	mux.Handle("POST /invitations/{token}/accept", authn.Wrap(http.HandlerFunc(inv.Accept)))

	return mux, nil
}

func newStores(ctx context.Context) (*store.Stores, error) {
	names := store.TableNames{
		Users:       os.Getenv("USERS_TABLE"),
		CareGroups:  os.Getenv("CARE_GROUPS_TABLE"),
		Memberships: os.Getenv("MEMBERSHIPS_TABLE"),
		Invitations: os.Getenv("INVITATIONS_TABLE"),
	}
	if names.Users == "" || names.CareGroups == "" || names.Memberships == "" || names.Invitations == "" {
		return nil, fmt.Errorf("USERS_TABLE/CARE_GROUPS_TABLE/MEMBERSHIPS_TABLE/INVITATIONS_TABLE must all be set")
	}
	// DYNAMODB_ENDPOINT is empty in Lambda (default AWS resolution); set for local/dev.
	client, err := store.NewClient(ctx, os.Getenv("DYNAMODB_ENDPOINT"))
	if err != nil {
		return nil, err
	}
	return store.New(client, names), nil
}
```

- [ ] **Step 18.2: Write the wiring test**

Create `api/cmd/lambda/mux_test.go`:

```go
package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
)

func setAppConfigEnv(t *testing.T) {
	t.Setenv("APPCONFIG_APPLICATION_ID", "a")
	t.Setenv("APPCONFIG_ENVIRONMENT_ID", "e")
	t.Setenv("APPCONFIG_PROFILE_ID", "p")
}

func TestNewMux_requiresTableEnv(t *testing.T) {
	setAppConfigEnv(t)
	if _, err := newMux(config.Config{Service: "api", Stage: "dev", Version: "0"}); err == nil {
		t.Fatal("expected error when table env is missing")
	}
}

func TestNewMux_healthServesWithoutContactingDynamo(t *testing.T) {
	setAppConfigEnv(t)
	t.Setenv("USERS_TABLE", "u")
	t.Setenv("CARE_GROUPS_TABLE", "c")
	t.Setenv("MEMBERSHIPS_TABLE", "m")
	t.Setenv("INVITATIONS_TABLE", "i")
	t.Setenv("AWS_REGION", "us-east-2")
	t.Setenv("AWS_ACCESS_KEY_ID", "x")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "x")
	t.Setenv("DYNAMODB_ENDPOINT", "http://127.0.0.1:1") // never contacted by /health

	h, err := newMux(config.Config{Service: "api", Stage: "dev", Version: "9.9"})
	if err != nil {
		t.Fatalf("newMux: %v", err)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("health code=%d", rec.Code)
	}
}
```

- [ ] **Step 18.3: Run, expect PASS; then build the whole api module**

Run: `cd api && go test ./... && go build ./...`
Expected: PASS + build clean. (`go build` exercises the same Linux/ARM cross-compile path CDK uses.)

- [ ] **Step 18.4: Commit**

```bash
git add api/cmd/lambda/mux.go api/cmd/lambda/mux_test.go
git commit -m "feat(api): wire B1 handlers and auth middleware into the mux"
```

**Acceptance Criteria — Task 18:**

- `newMux` returns an error if any `*_TABLE` env var is missing.
- With all env set, `GET /health` returns 200 without contacting DynamoDB, and the six authed routes are registered.
- `go build ./...` succeeds in `api`.

---

### Task 19: Deploy to dev and run the end-to-end smoke

> This is the validation DynamoDB Local can't provide: a **real Cognito sign-in** through the **JWT
> authorizer**, exercising JIT provisioning and the full invite/accept path. Maps to spec §13.

**Files:** none (operational).

- [ ] **Step 19.1: Deploy the dev stacks**

Either push the branch and let the PR `deploy-dev` job run, or locally:

```bash
cd infra && pnpm exec cdk deploy CaregiverDev-Shared CaregiverDev-Api --context stage=dev --require-approval never
```

Capture the outputs: `HttpApiUrl`, `UserPoolId`, `UserPoolClientId`.

- [ ] **Step 19.2: Create two confirmed test users**

```bash
POOL=<UserPoolId>
for u in alice@example.com bob@example.com; do
  aws cognito-idp admin-create-user --user-pool-id "$POOL" --username "$u" \
    --user-attributes Name=email,Value="$u" Name=email_verified,Value=true Name=name,Value="${u%@*}" \
    --message-action SUPPRESS
  aws cognito-idp admin-set-user-password --user-pool-id "$POOL" --username "$u" \
    --password 'Test1234!' --permanent
done
```

- [ ] **Step 19.3: Get an access token**

```bash
CLIENT=<UserPoolClientId>
TOKEN=$(aws cognito-idp admin-initiate-auth --user-pool-id "$POOL" --client-id "$CLIENT" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=alice@example.com,PASSWORD='Test1234!' \
  --query 'AuthenticationResult.AccessToken' --output text)
```

> Requires the app client to allow `ADMIN_USER_PASSWORD_AUTH` (enabled in Task 16). If you removed
> that flow, obtain the token via an SRP client instead.

- [ ] **Step 19.4: Walk the full path**

```bash
API=<HttpApiUrl>

# Unauthed call is rejected by the JWT authorizer:
curl -s -o /dev/null -w '%{http_code}\n' "$API/me"            # expect 401

# /me provisions Alice (JIT) and returns empty memberships:
curl -s "$API/me" -H "Authorization: Bearer $TOKEN"           # expect {"user":...,"memberships":[]}

# Alice creates a care group → she's Admin:
GID=$(curl -s "$API/care-groups" -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"Mom"}' | jq -r .care_group_id)

# Alice invites Bob:
TOK=$(curl -s "$API/care-groups/$GID/invitations" -H "Authorization: Bearer $TOKEN" \
  -d '{"email":"bob@example.com","role":"caregiver"}' | jq -r .token)

# Bob signs in, discovers the invite in-app, accepts:
BTOKEN=$(aws cognito-idp admin-initiate-auth --user-pool-id "$POOL" --client-id "$CLIENT" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=bob@example.com,PASSWORD='Test1234!' \
  --query 'AuthenticationResult.AccessToken' --output text)
curl -s "$API/invitations/mine" -H "Authorization: Bearer $BTOKEN"     # expect the pending invite
curl -s "$API/invitations/$TOK/accept" -X POST -H "Authorization: Bearer $BTOKEN"  # expect {care_group_id,role}

# Bob now sees the group:
curl -s "$API/me" -H "Authorization: Bearer $BTOKEN"          # memberships include the group as caregiver
```

**Acceptance Criteria — Task 19:**

- Unauthed `/me` → 401 (JWT authorizer rejects).
- Alice's first `/me` auto-provisions her and returns empty memberships; creating a group makes her Admin.
- Bob (no email sent) discovers the invite via `/invitations/mine` and accepts; his `/me` then shows the group as `caregiver`.
- No email was sent anywhere in the flow.

---

### Task 20: Open the PR

**Files:** none (operational).

- [ ] **Step 20.1: Push and open the PR**

```bash
git push -u origin <b1-branch>
gh pr create --title "feat: B1 data model & identity (multi-tenant foundation)" \
  --body "Implements docs/specs/2026-06-11-b1-data-model-identity-design.md. See docs/plans/2026-06-11-b1-data-model-identity.md." \
  --base main
```

- [ ] **Step 20.2: Verify CI is green**

Run: `gh pr checks --watch`
Expected: `lint`, `go-lint-test` (Go unit + DynamoDB-Local integration via Docker on the runner), `cdk-diff`, and `deploy-dev` all pass. The `cdk-diff` comment should show the four tables, the user pool, and the authorizer + routes being added.

- [ ] **Step 20.3: Hand off for merge**

Do not auto-merge. Report CI status + the cdk-diff summary and let the maintainer merge (prod deploy runs on merge per F1's `cd-main`).

**Acceptance Criteria — Task 20:**

- PR opens with all required checks green.
- The cdk-diff comment shows only the intended new resources (4 tables, user pool + client, JWT authorizer, 6 routes, IAM grants) — no unexpected deletions.

---

## Definition of done (maps to spec §13)

- [ ] Four DynamoDB tables + Cognito user pool + JWT authorizer deploy via CDK to dev (and synth clean for prod).
- [ ] A real user signs in, `GET /me` auto-provisions them, creates a care group (Admin), invites a second user, who accepts **in-app** — no email sent (Task 19 smoke).
- [ ] The isolation suite passes: no caregiver can reach a group they don't belong to through any endpoint; admin-only actions reject caregivers (Task 14).
- [ ] The OpenAPI contract generates Go server types; Swift client regenerates (or is recorded blocked-on-toolchain for C1) (Task 2).
- [ ] All checks green in CI; the deployed-dev smoke of sign-in → accept passes (Tasks 19–20).
