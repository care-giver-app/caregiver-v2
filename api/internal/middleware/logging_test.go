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
	if _, ok := got["bytes"]; !ok {
		t.Fatalf("bytes missing")
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

func TestRequestLoggerKeepsCommittedStatusOnPanic(t *testing.T) {
	var buf bytes.Buffer
	base := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)
	h := RequestLogger(base)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusAccepted) // commits 202
		panic("after header")
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/x", nil))

	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202 (committed status must not be overwritten)", rec.Code)
	}
	got := lastJSONLine(t, buf.String())
	if got["status"] != float64(http.StatusAccepted) {
		t.Fatalf("access line status = %v, want 202", got["status"])
	}
	if !strings.Contains(buf.String(), "\"msg\":\"panic\"") {
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
