// Package logger wraps slog with the structured fields required across all
// Caregiver services: service, env. Per-request fields (request_id, user_id,
// tenant_id) are attached at handler boundaries.
package logger

import (
	"io"
	"log/slog"
	"os"
)

// New returns a JSON logger writing to stdout.
func New(service, env string) *slog.Logger {
	return NewWithWriter(os.Stdout, service, env)
}

// NewWithWriter is the same as New but writes to the provided writer.
// Used by tests.
func NewWithWriter(w io.Writer, service, env string) *slog.Logger {
	h := slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})
	return slog.New(h).With("service", service, "env", env)
}
