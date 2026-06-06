package logger

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestNewProducesJSON(t *testing.T) {
	var buf bytes.Buffer
	log := NewWithWriter(&buf, "test-service", "dev")
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
