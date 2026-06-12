package handlers

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

// Templates serves the read-only, embedded tracker-template catalog.
type Templates struct{}

func NewTemplates() *Templates { return &Templates{} }

func (h *Templates) List(w http.ResponseWriter, r *http.Request) {
	httpx.WriteJSON(w, http.StatusOK, domain.Templates())
}
