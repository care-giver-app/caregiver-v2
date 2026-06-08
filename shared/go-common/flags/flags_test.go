package flags

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestClient_Get_ReturnsDecodedFlags(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"flags_demo": map[string]any{"enabled": true},
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	flags, err := c.Get(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	demo, ok := flags["flags_demo"].(map[string]any)
	if !ok {
		t.Fatalf("flags_demo not present: %v", flags)
	}
	if demo["enabled"] != true {
		t.Errorf("expected enabled=true, got %v", demo["enabled"])
	}
}
