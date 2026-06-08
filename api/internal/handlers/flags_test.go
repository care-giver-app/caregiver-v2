package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

type fakeFlagSource struct {
	flags map[string]any
	err   error
}

func (f fakeFlagSource) Get(ctx context.Context) (map[string]any, error) {
	return f.flags, f.err
}

func TestFlagsHandler_ReturnsFlagsJSON(t *testing.T) {
	h := NewFlags(fakeFlagSource{flags: map[string]any{"flags_demo": map[string]any{"enabled": true}}}, nil)
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
	h := NewFlags(fakeFlagSource{err: errors.New("boom")}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/flags", nil))
	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rr.Code)
	}
}
