package logger

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"strings"
	"testing"
)

func TestNewProducesJSON(t *testing.T) {
	var buf bytes.Buffer
	log := NewWithWriter(&buf, "test-service", "dev", slog.LevelInfo)
	log.Info("hello", "k", "v")

	line := strings.TrimSpace(buf.String())
	var got map[string]any
	if err := json.Unmarshal([]byte(line), &got); err != nil {
		t.Fatalf("not valid JSON: %v\nline: %s", err, line)
	}
	if got["msg"] != "hello" {
		t.Errorf("expected msg=hello, got %v", got["msg"])
	}
	if got["service"] != "test-service" {
		t.Errorf("expected service=test-service, got %v", got["service"])
	}
	if got["env"] != "dev" {
		t.Errorf("expected env=dev, got %v", got["env"])
	}
	if got["k"] != "v" {
		t.Errorf("expected k=v, got %v", got["k"])
	}
}

func TestParseLevel(t *testing.T) {
	cases := map[string]slog.Level{
		"debug":   slog.LevelDebug,
		"DEBUG":   slog.LevelDebug,
		" info ":  slog.LevelInfo,
		"warn":    slog.LevelWarn,
		"warning": slog.LevelWarn,
		"error":   slog.LevelError,
		"":        slog.LevelInfo,
		"bogus":   slog.LevelInfo,
	}
	for in, want := range cases {
		if got := ParseLevel(in); got != want {
			t.Errorf("ParseLevel(%q) = %v, want %v", in, got, want)
		}
	}
}

func TestLevelFromEnv(t *testing.T) {
	t.Setenv("LOG_LEVEL", "debug")
	if got := LevelFromEnv(); got != slog.LevelDebug {
		t.Errorf("LevelFromEnv() = %v, want Debug", got)
	}
}

func TestNewWithWriterRespectsLevel(t *testing.T) {
	var buf bytes.Buffer
	log := NewWithWriter(&buf, "s", "dev", slog.LevelInfo)
	log.Debug("should-not-appear")
	if strings.Contains(buf.String(), "should-not-appear") {
		t.Errorf("debug line emitted at info level: %s", buf.String())
	}
}
