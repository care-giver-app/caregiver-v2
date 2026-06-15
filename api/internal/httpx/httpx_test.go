package httpx

import (
	"bytes"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

func TestServerErrorLogsAndWrites(t *testing.T) {
	var buf bytes.Buffer
	log := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)
	r := httptest.NewRequest(http.MethodGet, "/x", nil)
	r = r.WithContext(logger.NewContext(r.Context(), log))
	rec := httptest.NewRecorder()

	ServerError(rec, r, errors.New("boom"), "lookup failed", "receiver_id", "rcv-1")

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "lookup failed") {
		t.Fatalf("client body missing message: %s", rec.Body.String())
	}
	out := buf.String()
	for _, want := range []string{"\"level\":\"ERROR\"", "boom", "receiver_id", "rcv-1"} {
		if !strings.Contains(out, want) {
			t.Fatalf("log missing %q: %s", want, out)
		}
	}
}
