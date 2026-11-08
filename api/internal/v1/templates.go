package v1

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// Templates serves GET /v1/tracker-templates, the embedded catalogue. Any
// signed-in caregiver may read it.
type Templates struct{}

func NewTemplates() *Templates { return &Templates{} }

func (h *Templates) List(w http.ResponseWriter, r *http.Request) {
	if requireCaller(w, r) == nil {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, domain.Templates())
}
