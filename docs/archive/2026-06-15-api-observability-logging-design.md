# API Observability — Request & Error Logging

- **Status:** Draft
- **Date:** 2026-06-15
- **Deciders:** Trevor Williams
- **Roadmap phase:** Interstitial hardening, inserted before C1 execution
- **Builds on:** F1 (`docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md`), B3a (`docs/specs/2026-06-12-b3a-core-care-domain-design.md`)

## 1. Purpose

The API is effectively silent in CloudWatch. There is a structured logger
(`shared/go-common/logger`) and slog is available, but nothing threads it through request handling:
no access log, no request correlation, and — most damaging — every `500` path writes a generic
message to the caller and **discards the underlying error**. Debugging a production failure today
means inferring what happened from a status code and a hand-written string like `"lookup failed"`.

This work makes the API observable: one structured access-log line per request, request-scoped
correlation fields on every line, the real error logged at every server-error site, and an
optional per-operation DynamoDB trace in dev. No new infrastructure.

## 2. Context

### 2.1 Current state (verified)

- `shared/go-common/logger/logger.go` produces JSON via `slog`, tagged with `service`/`env`, fixed at
  `LevelInfo`. Its doc comment promises "per-request fields (request_id, user_id, tenant_id) are
  attached at handler boundaries" — that was never built.
- `api/cmd/lambda/main.go` constructs a logger, uses it for two startup lines, and **never passes it
  to `newMux` or any handler**. Request handling has no logger.
- `api/cmd/lambda/mux.go` wires routes; the only middleware is `authn.Wrap`, which logs nothing.
- Handlers write errors via `httpx.WriteError` and **drop the `err`**. Example from
  `api/internal/handlers/events.go`:

  ```go
  if err := h.stores.Events.Put(r.Context(), e); err != nil {
      httpx.WriteError(w, http.StatusInternalServerError, "log failed") // err discarded
      return
  }
  ```

  The same swallow occurs at ~15 server-error sites across handlers and `middleware/auth.go`
  (`"provisioning failed"`, `"auth load failed"`).

- Panics produce nothing useful — there is no recovery/logging seam.

### 2.2 Decisions locked during brainstorming

| Decision                | Choice                                                                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scope                   | Full request observability: per-request access log **plus** real error logging.                                                                                                 |
| PII policy              | **IDs only.** Log `request_id`, `user_id` (Cognito sub), and resource IDs. Never email, name, event values, or request bodies.                                                  |
| Logger propagation      | **Request-scoped logger threaded via `context`** (not constructor injection into handler structs).                                                                              |
| Endpoint identification | Log both the concrete `path` and the matched `route` pattern (`GET /receivers/{receiverId}`).                                                                                   |
| DynamoDB visibility     | **AWS SDK middleware** logs every op (operation, duration, ok, err) — not per-repo instrumentation.                                                                             |
| Log levels              | Env-configurable via `LOG_LEVEL` (default `info`). DynamoDB op trace at **Debug**; handler failures at **Error**. dev → `debug`, prod → `info`.                                 |
| Double-logging          | Accepted in dev: a failed op yields an SDK Debug trace line **and** a handler Error line (complementary, not redundant). Suppressed in prod because the Debug line is filtered. |

### 2.3 Non-goals (YAGNI)

- No metrics / EMF, no CloudWatch custom metrics.
- No X-Ray / distributed tracing.
- No log sampling or rate limiting.
- No change to client-facing error responses (callers still get the existing generic messages).
- No request/response body logging.

## 3. Design

### 3.1 Logger-in-context helpers (`shared/go-common/logger/context.go`)

The channel everything else uses. Two functions plus an unexported context key:

- `func NewContext(ctx context.Context, l *slog.Logger) context.Context`
- `func FromContext(ctx context.Context) *slog.Logger` — returns the stored logger, or
  `slog.Default()` if none is set (so handlers and tests never nil-panic).

### 3.2 Configurable level (`shared/go-common/logger/logger.go`)

- Add a level parameter sourced from `LOG_LEVEL` (`debug`/`info`/`warn`/`error`, default `info`,
  case-insensitive). Parsing lives in the logger package; `config`/stage wiring sets the env per
  stage (dev → `debug`, prod → `info`).
- `New`/`NewWithWriter` accept the level (or read it from env). Existing `service`/`env` `.With`
  tagging is preserved.

### 3.3 Request-logging middleware (`api/internal/middleware/logging.go`)

A `func(base *slog.Logger) func(http.Handler) http.Handler` that wraps the **whole mux once**
(outermost), so it runs before routing on the way in and after routing on the way out:

1. Resolve `request_id` from the API Gateway v2 context (`core.GetAPIGatewayV2ContextFromContext` →
   `reqCtx.RequestID`); generate a fallback UUID if absent.
2. Build the request-scoped logger: `base.With("request_id", rid, "method", r.Method, "path",
r.URL.Path)` and store it via `logger.NewContext`.
3. Wrap `http.ResponseWriter` to capture `status` and `bytes` written (default 200 if
   `WriteHeader` is never called).
4. `defer` a `recover()`: on panic, log at Error (`panic`, recovered value, stack) and write a `500`
   if nothing has been written yet.
5. After `next.ServeHTTP`, emit **one** access line at Info: `status`, `duration_ms`, and `route`
   (read from `r.Pattern`, populated by the mux since Go 1.23; fall back to method+path when empty).

### 3.4 Auth middleware enrichment (`api/internal/middleware/auth.go`)

Once the Cognito `sub` is resolved, enrich the request-scoped logger:
`logger.NewContext(ctx, logger.FromContext(ctx).With("user_id", sub))` before calling downstream.
Every subsequent line (access, handler error, DynamoDB op) is then attributed to the user. IDs only
— no email on log lines. The existing `auth load failed` / `provisioning failed` sites adopt the
error helper (§3.5).

### 3.5 Server-error helper (`api/internal/httpx/httpx.go`)

```go
func ServerError(w http.ResponseWriter, r *http.Request, err error, msg string, attrs ...any)
```

Logs the **underlying `err`** at Error via `logger.FromContext(r.Context())` (including any extra
`attrs` such as `care_group_id`, `receiver_id`), then delegates to `WriteError(w, 500, msg)` so the
client response is unchanged. Every `WriteError(w, http.StatusInternalServerError, …)` site that has
an `err` in scope is migrated to `ServerError`. 4xx client errors stay quiet — they are not failures
and `WriteError` is retained for them.

### 3.6 DynamoDB SDK middleware (`shared/go-common/store`)

Register a middleware in `store.NewClient` (via `config.WithAPIOptions` / appending to the call
stack) that wraps every DynamoDB API call:

- Captures operation name (`middleware.GetOperationName`), `duration_ms`, and outcome.
- On success: log at **Debug** (`dynamodb op`, `operation`, `duration_ms`, `ok=true`).
- On failure: log at **Debug** (`ok=false`, `err`) — the authoritative error line remains the
  handler's `ServerError` at Error. The op error still bubbles up unchanged.
- Pulls the logger from the operation's context (`logger.FromContext`), so each op line inherits
  `request_id`/`user_id` from the request. (Handlers already pass `r.Context()` to store calls.)

Because op lines are Debug, they appear in dev and are filtered in prod.

### 3.7 Wiring (`api/cmd/lambda/main.go`, `mux.go`)

- `newMux` gains a `*slog.Logger` parameter; `main` passes the base logger (already carrying
  `service`/`env`) so the logging middleware can derive request-scoped children.
- The logging middleware wraps the returned mux before `httpadapter.NewV2`.

## 4. Data flow (a single request)

```
APIGW ─▶ logging mw ──(request_id, method, path; logger→ctx)──▶ mux (routing sets r.Pattern)
            │                                                     │
            │                                              authn.Wrap (user_id → ctx logger)
            │                                                     │
            │                                                  handler ──▶ store ──▶ DynamoDB
            │                                                     │           │
            │                                          err? ServerError       SDK mw logs op (Debug)
            │                                          (Error: real err)
            ◀── access line (status, duration_ms, route) at Info ─┘
```

## 5. Error handling

- **Server errors (5xx):** logged at Error with the underlying `err` + correlation fields; client
  still receives the existing generic message.
- **Client errors (4xx):** not logged (not failures). Visible via the access line's `status`.
- **Panics:** recovered in the logging middleware, logged at Error with stack, returned as `500`.
- **Logger absent from context:** `FromContext` falls back to `slog.Default()`; no panics.

## 6. Testing

- **logging middleware** (`logging_test.go`): using `logger.NewWithWriter(buf, …)`, assert the access
  line carries `request_id`, `method`, `path`, `route`, `status`, `duration_ms`; assert a handler
  that panics is recovered, logged at Error, and yields `500`; assert status capture for non-200.
- **httpx.ServerError**: assert the underlying `err` and extra `attrs` appear in the emitted line and
  that the client body/status is unchanged from `WriteError`.
- **auth middleware**: assert `user_id` is attached to the request-scoped logger and that the
  `auth load failed` path now logs the real error.
- **logger level parsing**: table test for `LOG_LEVEL` values + default.
- **store SDK middleware**: assert a success logs at Debug with `operation`/`ok=true` and a failure
  logs `ok=false` with the error, using the existing testcontainers DynamoDB suite.
- Full `go test ./...` for `api` and `go-common` (Docker required).

## 7. Rollout

- Single PR off `main` (per repo convention; Trevor merges). No data migration, no contract change,
  so no OpenAPI codegen.
- `LOG_LEVEL` env set per stage in CDK (`infra`): dev → `debug`, prod → `info`. Absent env defaults
  to `info`, so deploy order is safe.

```

```
