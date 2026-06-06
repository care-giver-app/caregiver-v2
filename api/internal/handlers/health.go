package handlers

import (
	"encoding/json"
	"net/http"
	"time"
)

type Health struct {
	version string
	now     func() time.Time
}

func NewHealth(version string, now func() time.Time) *Health {
	if now == nil {
		now = time.Now
	}
	return &Health{version: version, now: now}
}

func (h *Health) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	resp := map[string]string{
		"status":    "ok",
		"version":   h.version,
		"timestamp": h.now().UTC().Format(time.RFC3339),
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
