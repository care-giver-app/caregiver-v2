package logger

import (
	"bytes"
	"context"
	"log/slog"
	"strings"
	"testing"
)

func TestFromContextReturnsStoredLogger(t *testing.T) {
	var buf bytes.Buffer
	l := NewWithWriter(&buf, "s", "dev", slog.LevelInfo)
	ctx := NewContext(context.Background(), l)

	FromContext(ctx).Info("hi")
	if !strings.Contains(buf.String(), "\"msg\":\"hi\"") {
		t.Fatalf("stored logger not used: %s", buf.String())
	}
}

func TestFromContextFallsBackToDefault(t *testing.T) {
	// No logger in context: must not panic and must return a usable logger.
	if FromContext(context.Background()) == nil {
		t.Fatal("FromContext returned nil")
	}
}
