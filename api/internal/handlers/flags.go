package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
)

type FlagSource interface {
	Get(ctx context.Context) (map[string]any, error)
}

type Flags struct {
	source FlagSource
}

// NewFlags builds a Flags handler.
func NewFlags(src FlagSource) *Flags {
	return &Flags{source: src}
}

func (h *Flags) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	flags, err := h.source.Get(r.Context())
	if err != nil {
		httpx.ServerError(w, r, err, "could not load flags")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(flags)
}
