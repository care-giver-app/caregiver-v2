package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

type fakeFlagSource struct {
	flags map[string]any
	err   error
}

func (f fakeFlagSource) Get(ctx context.Context) (map[string]any, error) {
	return f.flags, f.err
}

func TestFlagsHandler_ReturnsFlagsJSON(t *testing.T) {
	h := NewFlags(fakeFlagSource{flags: map[string]any{"flags_demo": map[string]any{"enabled": true}}})
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/flags", nil))

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rr.Code, rr.Body.String())
	}
	var got map[string]any
	if err := json.NewDecoder(rr.Body).Decode(&got); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	demo, ok := got["flags_demo"].(map[string]any)
	if !ok || demo["enabled"] != true {
		t.Errorf("expected flags_demo.enabled=true, got %v", got)
	}
}

func TestFlagsHandler_ReturnsInternalServerErrorOnSourceFailure(t *testing.T) {
	var buf bytes.Buffer
	log := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)

	h := NewFlags(fakeFlagSource{err: errors.New("boom")})
	req := httptest.NewRequest(http.MethodGet, "/flags", nil)
	req = req.WithContext(logger.NewContext(req.Context(), log))

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), "could not load flags") {
		t.Errorf("expected client body to contain 'could not load flags', got: %s", rr.Body.String())
	}
	logOutput := buf.String()
	if !strings.Contains(logOutput, "boom") {
		t.Errorf("expected log to contain 'boom', got: %s", logOutput)
	}
	if !strings.Contains(logOutput, "server error") {
		t.Errorf("expected log to contain 'server error', got: %s", logOutput)
	}
}
