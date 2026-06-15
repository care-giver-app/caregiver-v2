# API Observability — Request & Error Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the API observable in CloudWatch — one structured access-log line per request, request-scoped correlation fields (`request_id`/`user_id`) on every line, the real error logged at every server-error site, and a per-operation DynamoDB trace in dev.

**Architecture:** A base `*slog.Logger` (already tagged `service`/`env`) is threaded from `main` into an outer request-logging middleware that attaches a request-scoped logger to `context` and emits the access line. Handlers and the store layer pull that logger from context via `logger.FromContext`. Errors flow through a new `httpx.ServerError` helper that logs the underlying error before writing the existing generic client response. DynamoDB visibility comes from an AWS SDK middleware registered in `store.NewClient`. Log level is env-configurable (`LOG_LEVEL`).

**Tech Stack:** Go 1.23.7, `log/slog`, AWS SDK Go v2 (`smithy-go/middleware`, `aws-sdk-go-v2/aws/middleware`), `aws-lambda-go-api-proxy/core`, `google/uuid`, testcontainers DynamoDB (`dynamotest`), AWS CDK (TypeScript).

**Spec:** `docs/specs/2026-06-15-api-observability-logging-design.md`

**Conventions:** Branch off `main`, open a PR, do NOT auto-merge (Trevor merges). Commit messages are Conventional Commits, lowercase subject (`feat: …`, `test: …`). Do NOT run `go get …@latest` (it bumps the go directive and breaks CI); `go mod tidy` is safe. Go store tests need Docker.

---

## Task 1: Configurable log level in the logger package

**Files:**

- Modify: `shared/go-common/logger/logger.go`
- Modify (test): `shared/go-common/logger/logger_test.go`

- [ ] **Step 1: Update the existing test to the new `NewWithWriter` signature and add a level-parsing test**

Replace the whole body of `shared/go-common/logger/logger_test.go` with:

```go
package logger

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"strings"
	"testing"
)

func TestNewProducesJSON(t *testing.T) {
	var buf bytes.Buffer
	log := NewWithWriter(&buf, "test-service", "dev", slog.LevelInfo)
	log.Info("hello", "k", "v")

	line := strings.TrimSpace(buf.String())
	var got map[string]any
	if err := json.Unmarshal([]byte(line), &got); err != nil {
		t.Fatalf("not valid JSON: %v\nline: %s", err, line)
	}
	if got["msg"] != "hello" {
		t.Errorf("expected msg=hello, got %v", got["msg"])
	}
	if got["service"] != "test-service" {
		t.Errorf("expected service=test-service, got %v", got["service"])
	}
	if got["env"] != "dev" {
		t.Errorf("expected env=dev, got %v", got["env"])
	}
	if got["k"] != "v" {
		t.Errorf("expected k=v, got %v", got["k"])
	}
}

func TestParseLevel(t *testing.T) {
	cases := map[string]slog.Level{
		"debug":   slog.LevelDebug,
		"DEBUG":   slog.LevelDebug,
		" info ":  slog.LevelInfo,
		"warn":    slog.LevelWarn,
		"warning": slog.LevelWarn,
		"error":   slog.LevelError,
		"":        slog.LevelInfo,
		"bogus":   slog.LevelInfo,
	}
	for in, want := range cases {
		if got := ParseLevel(in); got != want {
			t.Errorf("ParseLevel(%q) = %v, want %v", in, got, want)
		}
	}
}

func TestNewWithWriterRespectsLevel(t *testing.T) {
	var buf bytes.Buffer
	log := NewWithWriter(&buf, "s", "dev", slog.LevelInfo)
	log.Debug("should-not-appear")
	if strings.Contains(buf.String(), "should-not-appear") {
		t.Errorf("debug line emitted at info level: %s", buf.String())
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `cd shared/go-common && go test ./logger/...`
Expected: FAIL — `NewWithWriter` takes 3 args / `ParseLevel` undefined.

- [ ] **Step 3: Implement the configurable level**

Replace the whole body of `shared/go-common/logger/logger.go` with:

```go
// Package logger wraps slog with the structured fields required across all
// Caregiver services: service, env. Per-request fields (request_id, user_id,
// tenant_id) are attached at handler boundaries.
package logger

import (
	"io"
	"log/slog"
	"os"
	"strings"
)

// New returns a JSON logger writing to stdout at the level from LOG_LEVEL.
func New(service, env string) *slog.Logger {
	return NewWithWriter(os.Stdout, service, env, LevelFromEnv())
}

// NewWithWriter is the same as New but writes to the provided writer at the
// given level. Used by tests.
func NewWithWriter(w io.Writer, service, env string, level slog.Level) *slog.Logger {
	h := slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level: level,
	})
	return slog.New(h).With("service", service, "env", env)
}

// LevelFromEnv reads LOG_LEVEL and returns the slog level, defaulting to Info.
func LevelFromEnv() slog.Level {
	return ParseLevel(os.Getenv("LOG_LEVEL"))
}

// ParseLevel maps a level string (case-insensitive) to slog.Level, defaulting
// to Info for unset or unrecognized values.
func ParseLevel(s string) slog.Level {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd shared/go-common && go test ./logger/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shared/go-common/logger/logger.go shared/go-common/logger/logger_test.go
git commit -m "feat: configurable log level in logger package"
```

---

## Task 2: Logger-in-context helpers

**Files:**

- Create: `shared/go-common/logger/context.go`
- Create (test): `shared/go-common/logger/context_test.go`

- [ ] **Step 1: Write the failing test**

Create `shared/go-common/logger/context_test.go`:

```go
package logger

import (
	"bytes"
	"context"
	"log/slog"
	"strings"
	"testing"
)

func TestFromContextReturnsStoredLogger(t *testing.T) {
	var buf bytes.Buffer
	l := NewWithWriter(&buf, "s", "dev", slog.LevelInfo)
	ctx := NewContext(context.Background(), l)

	FromContext(ctx).Info("hi")
	if !strings.Contains(buf.String(), "\"msg\":\"hi\"") {
		t.Fatalf("stored logger not used: %s", buf.String())
	}
}

func TestFromContextFallsBackToDefault(t *testing.T) {
	// No logger in context: must not panic and must return a usable logger.
	if FromContext(context.Background()) == nil {
		t.Fatal("FromContext returned nil")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd shared/go-common && go test ./logger/...`
Expected: FAIL — `NewContext`/`FromContext` undefined.

- [ ] **Step 3: Implement the context helpers**

Create `shared/go-common/logger/context.go`:

```go
package logger

import (
	"context"
	"log/slog"
)

type ctxKey struct{}

// NewContext returns a copy of ctx carrying the request-scoped logger.
func NewContext(ctx context.Context, l *slog.Logger) context.Context {
	return context.WithValue(ctx, ctxKey{}, l)
}

// FromContext returns the logger stored by NewContext, or slog.Default() when
// none is present so callers never nil-panic.
func FromContext(ctx context.Context) *slog.Logger {
	if l, ok := ctx.Value(ctxKey{}).(*slog.Logger); ok && l != nil {
		return l
	}
	return slog.Default()
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd shared/go-common && go test ./logger/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shared/go-common/logger/context.go shared/go-common/logger/context_test.go
git commit -m "feat: request-scoped logger context helpers"
```

---

## Task 3: DynamoDB SDK logging middleware

**Files:**

- Create: `shared/go-common/store/logging.go`
- Modify: `shared/go-common/store/store.go:69-79` (`NewClient`)
- Create (test): `shared/go-common/store/logging_test.go`

- [ ] **Step 1: Write the failing test**

Create `shared/go-common/store/logging_test.go`:

```go
package store_test

import (
	"bytes"
	"context"
	"log/slog"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestDynamoOpsLoggedAtDebug(t *testing.T) {
	stores := dynamotest.Start(t)

	var buf bytes.Buffer
	log := logger.NewWithWriter(&buf, "s", "test", slog.LevelDebug)
	ctx := logger.NewContext(context.Background(), log)

	// A lookup for a missing user still issues a GetItem against DynamoDB.
	_, _ = stores.Users.Get(ctx, "no-such-user")

	out := buf.String()
	if !strings.Contains(out, "\"msg\":\"dynamodb op\"") {
		t.Fatalf("no dynamodb op line: %s", out)
	}
	if !strings.Contains(out, "\"operation\":\"GetItem\"") {
		t.Fatalf("operation name missing: %s", out)
	}
}

func TestDynamoOpsSilentAtInfo(t *testing.T) {
	stores := dynamotest.Start(t)

	var buf bytes.Buffer
	log := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)
	ctx := logger.NewContext(context.Background(), log)

	_, _ = stores.Users.Get(ctx, "no-such-user")

	if strings.Contains(buf.String(), "dynamodb op") {
		t.Fatalf("op line emitted at info level: %s", buf.String())
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd shared/go-common && go test ./store/ -run TestDynamoOps -v`
Expected: FAIL — no `dynamodb op` line in output (Docker must be running).

- [ ] **Step 3: Implement the SDK middleware**

Create `shared/go-common/store/logging.go`:

```go
package store

import (
	"context"
	"time"

	awsmiddleware "github.com/aws/aws-sdk-go-v2/aws/middleware"
	"github.com/aws/smithy-go/middleware"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

// logOps registers a Finalize middleware that logs every DynamoDB API call at
// Debug with operation name, duration, and outcome. The logger is pulled from
// the operation's context so each line inherits request_id/user_id.
func logOps(stack *middleware.Stack) error {
	return stack.Finalize.Add(
		middleware.FinalizeMiddlewareFunc(
			"CaregiverDynamoLog",
			func(ctx context.Context, in middleware.FinalizeInput, next middleware.FinalizeHandler) (
				middleware.FinalizeOutput, middleware.Metadata, error,
			) {
				start := time.Now()
				out, md, err := next.HandleFinalize(ctx, in)
				log := logger.FromContext(ctx)
				dur := time.Since(start).Milliseconds()
				op := awsmiddleware.GetOperationName(ctx)
				if err != nil {
					log.Debug("dynamodb op", "operation", op, "duration_ms", dur, "ok", false, "err", err.Error())
				} else {
					log.Debug("dynamodb op", "operation", op, "duration_ms", dur, "ok", true)
				}
				return out, md, err
			},
		),
		middleware.After,
	)
}
```

- [ ] **Step 4: Register the middleware in `NewClient`**

In `shared/go-common/store/store.go`, replace the `NewClient` return statement (lines 74-78):

```go
	return dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
	}), nil
```

with:

```go
	return dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
		o.APIOptions = append(o.APIOptions, logOps)
	}), nil
```

- [ ] **Step 5: Tidy modules (NOT `go get`)**

Run: `cd shared/go-common && go mod tidy`
Expected: `github.com/aws/smithy-go` and `github.com/aws/aws-sdk-go-v2/aws/middleware` resolve as direct deps at their existing versions. Verify the `go` directive in `go.mod` is unchanged (still `1.23.7`); if it changed, revert that line.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd shared/go-common && go test ./store/ -run TestDynamoOps -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add shared/go-common/store/logging.go shared/go-common/store/store.go shared/go-common/go.mod shared/go-common/go.sum
git commit -m "feat: log dynamodb operations via sdk middleware"
```

---

## Task 4: `httpx.ServerError` helper

**Files:**

- Modify: `api/internal/httpx/httpx.go`
- Create (test): `api/internal/httpx/httpx_test.go`

- [ ] **Step 1: Write the failing test**

Create `api/internal/httpx/httpx_test.go`:

```go
package httpx

import (
	"bytes"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

func TestServerErrorLogsAndWrites(t *testing.T) {
	var buf bytes.Buffer
	log := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)
	r := httptest.NewRequest(http.MethodGet, "/x", nil)
	r = r.WithContext(logger.NewContext(r.Context(), log))
	rec := httptest.NewRecorder()

	ServerError(rec, r, errors.New("boom"), "lookup failed", "receiver_id", "rcv-1")

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "lookup failed") {
		t.Fatalf("client body missing message: %s", rec.Body.String())
	}
	out := buf.String()
	for _, want := range []string{"\"level\":\"ERROR\"", "boom", "receiver_id", "rcv-1"} {
		if !strings.Contains(out, want) {
			t.Fatalf("log missing %q: %s", want, out)
		}
	}
	// PII guard: the underlying error is logged, but the generic client message
	// is the only thing the caller sees.
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd api && go test ./internal/httpx/...`
Expected: FAIL — `ServerError` undefined.

- [ ] **Step 3: Implement `ServerError`**

In `api/internal/httpx/httpx.go`, add the `logger` import. The import block becomes:

```go
import (
	"encoding/json"
	"net/http"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)
```

Append after `WriteError`:

```go
// ServerError logs the underlying err (plus any extra structured attrs) at Error
// using the request-scoped logger, then writes the generic 500 response. The
// client never sees err — only msg. Use this at every server-error site that has
// an error in scope; keep WriteError for 4xx client errors.
func ServerError(w http.ResponseWriter, r *http.Request, err error, msg string, attrs ...any) {
	errStr := ""
	if err != nil {
		errStr = err.Error()
	}
	args := append([]any{"err", errStr, "client_msg", msg}, attrs...)
	logger.FromContext(r.Context()).Error("server error", args...)
	WriteError(w, http.StatusInternalServerError, msg)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd api && go test ./internal/httpx/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add api/internal/httpx/httpx.go api/internal/httpx/httpx_test.go
git commit -m "feat: add httpx.ServerError helper that logs the underlying error"
```

---

## Task 5: Request-logging middleware

**Files:**

- Create: `api/internal/middleware/logging.go`
- Create (test): `api/internal/middleware/logging_test.go`

- [ ] **Step 1: Write the failing test**

Create `api/internal/middleware/logging_test.go`:

```go
package middleware

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

func lastJSONLine(t *testing.T, s string) map[string]any {
	t.Helper()
	lines := strings.Split(strings.TrimSpace(s), "\n")
	var got map[string]any
	if err := json.Unmarshal([]byte(lines[len(lines)-1]), &got); err != nil {
		t.Fatalf("not JSON: %v\n%s", err, s)
	}
	return got
}

func TestRequestLoggerEmitsAccessLine(t *testing.T) {
	var buf bytes.Buffer
	base := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /receivers/{receiverId}", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	})
	h := RequestLogger(base)(mux)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/receivers/abc", nil))

	got := lastJSONLine(t, buf.String())
	if got["msg"] != "request" {
		t.Fatalf("msg = %v, want request", got["msg"])
	}
	if got["status"] != float64(http.StatusTeapot) {
		t.Fatalf("status = %v, want 418", got["status"])
	}
	if got["route"] != "GET /receivers/{receiverId}" {
		t.Fatalf("route = %v, want templated pattern", got["route"])
	}
	if got["method"] != "GET" || got["path"] != "/receivers/abc" {
		t.Fatalf("method/path = %v %v", got["method"], got["path"])
	}
	if got["request_id"] == nil || got["request_id"] == "" {
		t.Fatalf("request_id missing")
	}
	if _, ok := got["duration_ms"]; !ok {
		t.Fatalf("duration_ms missing")
	}
}

func TestRequestLoggerRecoversPanic(t *testing.T) {
	var buf bytes.Buffer
	base := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)
	h := RequestLogger(base)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("kaboom")
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/x", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if !strings.Contains(buf.String(), "\"msg\":\"panic\"") || !strings.Contains(buf.String(), "kaboom") {
		t.Fatalf("panic not logged: %s", buf.String())
	}
}

func TestRequestLoggerProvidesContextLogger(t *testing.T) {
	var buf bytes.Buffer
	base := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)
	h := RequestLogger(base)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		logger.FromContext(r.Context()).Info("from-handler")
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/x", nil))

	if !strings.Contains(buf.String(), "from-handler") || !strings.Contains(buf.String(), "request_id") {
		t.Fatalf("handler did not get request-scoped logger: %s", buf.String())
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd api && go test ./internal/middleware/ -run TestRequestLogger -v`
Expected: FAIL — `RequestLogger` undefined.

- [ ] **Step 3: Implement the middleware**

Create `api/internal/middleware/logging.go`:

```go
package middleware

import (
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/awslabs/aws-lambda-go-api-proxy/core"
	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

// statusRecorder captures the response status code and byte count so the access
// line can report them. Defaults to 200 until WriteHeader is called.
type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

// RequestLogger wraps the mux with: a request-scoped logger in context
// (request_id/method/path), panic recovery, and exactly one access-log line per
// request (status/duration_ms/route). It must wrap the mux so r.Pattern (Go
// 1.23) is populated by routing before the access line is emitted.
func RequestLogger(base *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			log := base.With("request_id", requestID(r), "method", r.Method, "path", r.URL.Path)
			r = r.WithContext(logger.NewContext(r.Context(), log))
			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

			defer func() {
				if rv := recover(); rv != nil {
					logger.FromContext(r.Context()).Error("panic",
						"recover", rv, "stack", string(debug.Stack()))
					if rec.bytes == 0 {
						rec.WriteHeader(http.StatusInternalServerError)
					}
				}
				logger.FromContext(r.Context()).Info("request",
					"status", rec.status,
					"duration_ms", time.Since(start).Milliseconds(),
					"route", route(r))
			}()

			next.ServeHTTP(rec, r)
		})
	}
}

// requestID prefers the API Gateway v2 request id; falls back to a generated UUID.
func requestID(r *http.Request) string {
	if reqCtx, ok := core.GetAPIGatewayV2ContextFromContext(r.Context()); ok && reqCtx.RequestID != "" {
		return reqCtx.RequestID
	}
	return uuid.NewString()
}

// route returns the matched template (e.g. "GET /receivers/{receiverId}") once
// routing has run, falling back to method+path when no pattern matched.
func route(r *http.Request) string {
	if r.Pattern != "" {
		return r.Pattern
	}
	return r.Method + " " + r.URL.Path
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd api && go test ./internal/middleware/ -run TestRequestLogger -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add api/internal/middleware/logging.go api/internal/middleware/logging_test.go
git commit -m "feat: request-logging middleware with access line and panic recovery"
```

---

## Task 6: Auth middleware — enrich logger + migrate its 500 sites

**Files:**

- Modify: `api/internal/middleware/auth.go:33-68`
- Modify (test): `api/internal/middleware/auth_test.go` (add one assertion)

- [ ] **Step 1: Add a failing test for user_id enrichment**

Append to `api/internal/middleware/auth_test.go` (the file already imports `context`, `net/http`, `net/http/httptest`, `testing`, `auth`, `dynamotest`; add `bytes`, `log/slog`, `strings`, and the `logger` import):

```go
func TestAuthenticator_AttachesUserIDToLogger(t *testing.T) {
	stores := dynamotest.Start(t)
	a := NewAuthenticator(stores)
	a.extract = func(r *http.Request) (claims, bool) {
		return claims{Sub: "sub-log", Email: "a@b.com", Name: "A"}, true
	}

	var buf bytes.Buffer
	base := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)

	h := a.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		logger.FromContext(r.Context()).Info("in-handler")
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req = req.WithContext(logger.NewContext(req.Context(), base))
	h.ServeHTTP(httptest.NewRecorder(), req)

	if !strings.Contains(buf.String(), "\"user_id\":\"sub-log\"") {
		t.Fatalf("user_id not attached to logger: %s", buf.String())
	}
}
```

Add to the import block of `auth_test.go`:

```go
	"bytes"
	"log/slog"
	"strings"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd api && go test ./internal/middleware/ -run TestAuthenticator_AttachesUserIDToLogger -v`
Expected: FAIL — no `user_id` field in the emitted line.

- [ ] **Step 3: Enrich the logger and migrate the 500 sites**

In `api/internal/middleware/auth.go`, replace the body of the `Wrap` closure (currently lines 34-67) with:

```go
		c, ok := m.extract(r)
		if !ok || c.Sub == "" {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		ctx := logger.NewContext(r.Context(), logger.FromContext(r.Context()).With("user_id", c.Sub))
		r = r.WithContext(ctx)
		email := domain.NormalizeEmail(c.Email)

		// Read-first: only write on a user's first request, so the steady-state
		// hot path is a read rather than a conditional write that always fails.
		if _, err := m.stores.Users.Get(ctx, c.Sub); errors.Is(err, store.ErrNotFound) {
			if _, cerr := m.stores.Users.CreateIfAbsent(ctx, domain.User{
				UserID: c.Sub, Email: email, Name: c.Name, CreatedAt: m.now().UTC(),
			}); cerr != nil {
				httpx.ServerError(w, r, cerr, "provisioning failed")
				return
			}
		} else if err != nil {
			httpx.ServerError(w, r, err, "auth load failed")
			return
		}

		ms, err := m.stores.Memberships.ListByUser(ctx, c.Sub)
		if err != nil {
			httpx.ServerError(w, r, err, "auth load failed")
			return
		}
		ac := &auth.AuthContext{UserID: c.Sub, Email: email, Memberships: make(map[string]domain.Role, len(ms))}
		for _, mem := range ms {
			ac.Memberships[mem.CareGroupID] = mem.Role
		}
		next.ServeHTTP(w, r.WithContext(auth.NewContext(ctx, ac)))
```

Add `"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"` to the import block of `auth.go`.

- [ ] **Step 4: Run the middleware tests to verify they pass**

Run: `cd api && go test ./internal/middleware/...`
Expected: PASS (existing auth tests + the new one).

- [ ] **Step 5: Commit**

```bash
git add api/internal/middleware/auth.go api/internal/middleware/auth_test.go
git commit -m "feat: attach user_id to request logger and log auth errors"
```

---

## Task 7: Migrate handler 500 sites to `ServerError`

**Files (modify):**

- `api/internal/handlers/events.go` (lines 49, 81, 112, 134, 168, 180)
- `api/internal/handlers/caregroups.go` (lines 53, 84, 95, 101, 112, 121)
- `api/internal/handlers/invitations.go` (lines 39, 48)
- `api/internal/handlers/me.go` (lines 41, 50)
- `api/internal/handlers/receivers.go` (lines 43, 51, 79, 96, 140, 155)
- `api/internal/handlers/trackers.go` (lines 59, 67, 84, 105, 119, 155, 170)

**Transformation rule (apply at every listed site):**

Each site currently looks like:

```go
if err := h.stores.X.Y(...); err != nil {
	httpx.WriteError(w, http.StatusInternalServerError, "MSG")
	return
}
```

or

```go
..., err := h.stores.X.Y(...)
if err != nil {
	httpx.WriteError(w, http.StatusInternalServerError, "MSG")
	return
}
```

Rewrite **only the `WriteError` call** to `ServerError`, passing the request `r` and the error variable in scope (almost always `err`):

```go
	httpx.ServerError(w, r, err, "MSG")
```

Keep the same `"MSG"` string so client responses are unchanged. The handler receiver is always `(w http.ResponseWriter, r *http.Request)`, so `r` is in scope at every site.

**Per-site notes (error variable names that are NOT `err`):**

- `caregroups.go:112` — message `"token generation failed"`: this is the error from token/random generation; use the error variable from that `if err := ...` (it is `err`). Verify by reading lines 108-113.
- All other listed sites use `err`. If any site's error is shadowed/named differently, use that name. **Do not invent a variable** — read the 3 lines above each call to confirm.

- [ ] **Step 1: Migrate `events.go`** — at lines 49, 81, 112, 134, 168, 180 change `httpx.WriteError(w, http.StatusInternalServerError, "MSG")` → `httpx.ServerError(w, r, err, "MSG")` (keep each existing MSG).

- [ ] **Step 2: Migrate `caregroups.go`** — lines 53, 84, 95, 101, 112, 121. Note line 101 is inside a nested block (a per-item loop / conditional) — confirm the error var name from the 3 preceding lines before editing.

- [ ] **Step 3: Migrate `invitations.go`** — lines 39, 48.

- [ ] **Step 4: Migrate `me.go`** — lines 41, 50.

- [ ] **Step 5: Migrate `receivers.go`** — lines 43, 51, 79, 96, 140, 155. Lines 43 and 51 are both inside `List`'s loop/aggregation — confirm each error var.

- [ ] **Step 6: Migrate `trackers.go`** — lines 59, 67, 84, 105, 119, 155, 170.

- [ ] **Step 7: Verify no 500 site still discards its error**

Run: `grep -rn "WriteError(w, http.StatusInternalServerError" api/internal/handlers/`
Expected: **no output** (every server-error site now uses `ServerError`). `WriteError` should remain only for 4xx statuses.

- [ ] **Step 8: Build and run the full api test suite**

Run: `cd api && go vet ./... && go test ./...`
Expected: PASS (Docker required for handler tests). Existing handler tests assert status codes and client bodies, which are unchanged by this migration.

- [ ] **Step 9: Commit**

```bash
git add api/internal/handlers/
git commit -m "feat: log underlying errors at handler server-error sites"
```

---

## Task 8: Wire the logger and middleware in main/mux

**Files:**

- Modify: `api/cmd/lambda/mux.go:16` (`newMux` signature) and the return wrapping
- Modify: `api/cmd/lambda/main.go:27` (pass logger to `newMux`)
- Modify (test): `api/cmd/lambda/mux_test.go` (update `newMux` call sites)

- [ ] **Step 1: Update `newMux` to accept the base logger and wrap with RequestLogger**

In `api/cmd/lambda/mux.go`:

- Change the signature `func newMux(cfg config.Config) (http.Handler, error) {` to:

```go
func newMux(cfg config.Config, log *slog.Logger) (http.Handler, error) {
```

- Add imports `"log/slog"` and the middleware package is already imported (`api/internal/middleware`). Confirm `middleware` import is present (it is, for `NewAuthenticator`).

- Change the final `return mux, nil` to wrap the mux:

```go
	return middleware.RequestLogger(log)(mux), nil
```

- [ ] **Step 2: Pass the logger from `main`**

In `api/cmd/lambda/main.go`, change line 27 from:

```go
	mux, err := newMux(cfg)
```

to:

```go
	mux, err := newMux(cfg, log)
```

- [ ] **Step 3: Update `newMux` call sites in `mux_test.go`**

Run: `grep -n "newMux(" api/cmd/lambda/mux_test.go`
For each call, add a logger argument. Use a discard logger so tests stay quiet:

```go
	testLog := logger.NewWithWriter(io.Discard, "test", "test", slog.LevelInfo)
	h, err := newMux(cfg, testLog)
```

Add imports to `mux_test.go` as needed: `"io"`, `"log/slog"`, and `"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"`.

- [ ] **Step 4: Build and test the lambda package**

Run: `cd api && go vet ./... && go test ./cmd/...`
Expected: PASS.

- [ ] **Step 5: Run the entire api + go-common suites**

Run: `cd api && go test ./... && cd ../shared/go-common && go test ./...`
Expected: PASS (Docker required).

- [ ] **Step 6: Commit**

```bash
git add api/cmd/lambda/mux.go api/cmd/lambda/main.go api/cmd/lambda/mux_test.go
git commit -m "feat: wire request-logging middleware into the api mux"
```

---

## Task 9: Set `LOG_LEVEL` per stage in infra

**Files:**

- Modify: `infra/lib/api-stack.ts:72-76` (Lambda `environment`)
- Modify (test): the infra stack test that asserts the API Lambda's environment (find it in Step 1)

- [ ] **Step 1: Find the infra test that asserts Lambda env vars**

Run: `grep -rln "SERVICE\|APP_VERSION\|Environment" infra/test/`
Open the matching test file to mirror its assertion style for the new `LOG_LEVEL` var.

- [ ] **Step 2: Add a failing test asserting LOG_LEVEL per stage**

In the infra test file from Step 1, add an assertion (adapt to the file's existing `Template`/`Match` pattern) that the API function's environment includes `LOG_LEVEL: 'debug'` for a dev synth and `LOG_LEVEL: 'info'` for a prod synth. Example shape:

```ts
template.hasResourceProperties('AWS::Lambda::Function', {
  Environment: {
    Variables: Match.objectLike({ LOG_LEVEL: 'debug' }),
  },
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd infra && pnpm test`
Expected: FAIL — `LOG_LEVEL` not present in the synthesized template.

- [ ] **Step 4: Add LOG_LEVEL to the Lambda environment**

In `infra/lib/api-stack.ts`, change the `environment` block (lines 72-76) to:

```ts
      environment: {
        SERVICE: 'api',
        STAGE: props.stage,
        APP_VERSION: props.version,
        LOG_LEVEL: props.stage === 'prod' ? 'info' : 'debug',
      },
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd infra && pnpm test`
Expected: PASS.

- [ ] **Step 6: Verify synth (dev + prod)**

Run: `cd infra && pnpm exec cdk synth --context stage=dev | grep -A6 "Environment" | grep LOG_LEVEL`
Expected: `LOG_LEVEL: debug` appears for the API function.

- [ ] **Step 7: Format and commit**

```bash
cd infra && pnpm exec prettier --write lib/api-stack.ts test/
git add infra/lib/api-stack.ts infra/test/
git commit -m "feat: set LOG_LEVEL per stage for the api lambda"
```

---

## Final verification

- [ ] **Full suites green**

Run:

```bash
cd shared/go-common && go test ./...
cd ../../api && go test ./...
cd ../infra && pnpm test
```

Expected: all PASS (Docker running for Go).

- [ ] **No discarded server errors remain**

Run: `grep -rn "WriteError(w, http.StatusInternalServerError" api/`
Expected: no output.

- [ ] **Manual sanity of log shape (optional, local)**

Confirm an access line is JSON with `request_id`, `method`, `path`, `route`, `status`, `duration_ms`, `service`, `env`, and (for authed routes) `user_id`.

- [ ] **Open PR (do NOT merge — Trevor merges)**

```bash
git push -u origin <branch>
gh pr create --title "feat: api request & error logging (observability)" --body "Implements docs/specs/2026-06-15-api-observability-logging-design.md"
```

---

## Spec coverage check

| Spec section                                 | Task                            |
| -------------------------------------------- | ------------------------------- |
| §3.1 Logger-in-context helpers               | 2                               |
| §3.2 Configurable level (`LOG_LEVEL`)        | 1, 9                            |
| §3.3 Request-logging middleware              | 5, 8                            |
| §3.4 Auth middleware enrichment              | 6                               |
| §3.5 `httpx.ServerError` + migrate 500s      | 4, 6, 7                         |
| §3.6 DynamoDB SDK middleware                 | 3                               |
| §3.7 Wiring (main/mux)                       | 8                               |
| §5 Panic recovery                            | 5                               |
| §6 Error handling (4xx stay quiet)           | 7 (WriteError retained for 4xx) |
| §7 Rollout (LOG_LEVEL per stage, no codegen) | 9                               |
