package handlers_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func TestTemplates_listReturnsCatalog(t *testing.T) {
	h := handlers.NewTemplates()
	req := httptest.NewRequest(http.MethodGet, "/tracker-templates", nil)
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{})
	rec := httptest.NewRecorder()
	h.List(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"template_id"`) {
		t.Fatalf("expected catalog, got %d %s", rec.Code, rec.Body.String())
	}
}
