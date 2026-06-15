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

// NewWithWriter builds a logger writing to w at the given level. It is the
// canonical constructor for callers needing a custom writer or level (e.g. tests).
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
	case "info":
		return slog.LevelInfo
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
