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
