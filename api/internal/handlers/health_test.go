package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHealthHandler_ReturnsOK(t *testing.T) {
	h := NewHealth("0.1.0", func() time.Time { return time.Date(2026, 6, 6, 12, 0, 0, 0, time.UTC) })

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatalf("invalid JSON body: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("expected status=ok, got %s", body["status"])
	}
	if body["version"] != "0.1.0" {
		t.Errorf("expected version=0.1.0, got %s", body["version"])
	}
	if body["timestamp"] != "2026-06-06T12:00:00Z" {
		t.Errorf("expected timestamp=2026-06-06T12:00:00Z, got %s", body["timestamp"])
	}
}
