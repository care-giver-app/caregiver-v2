package handlers

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
)

type FlagSource interface {
	Get(ctx context.Context) (map[string]any, error)
}

type Flags struct {
	source FlagSource
	log    *slog.Logger
}

// NewFlags builds a Flags handler. Pass nil for log to use slog.Default().
func NewFlags(src FlagSource, log *slog.Logger) *Flags {
	if log == nil {
		log = slog.Default()
	}
	return &Flags{source: src, log: log}
}

func (h *Flags) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	flags, err := h.source.Get(r.Context())
	if err != nil {
		h.log.ErrorContext(r.Context(), "flags fetch failed", "err", err)
		http.Error(w, "could not load flags", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(flags)
}
