package handlers

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Members struct{ stores *store.Stores }

func NewMembers(s *store.Stores) *Members { return &Members{stores: s} }

type memberItem struct {
	UserID string `json:"user_id"`
	Name   string `json:"name"`
	Role   string `json:"role"`
}

func (h *Members) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	groupID := r.PathValue("careGroupId")
	if !httpx.RequireMember(w, ac, groupID) {
		return
	}
	ctx := r.Context()
	memberships, err := h.stores.Memberships.ListByGroup(ctx, groupID)
	if err != nil {
		httpx.ServerError(w, r, err, "members load failed")
		return
	}
	ids := make([]string, 0, len(memberships))
	for _, m := range memberships {
		ids = append(ids, m.UserID)
	}
	users, err := h.stores.Users.BatchGet(ctx, ids)
	if err != nil {
		httpx.ServerError(w, r, err, "user load failed")
		return
	}
	out := make([]memberItem, 0, len(memberships))
	for _, m := range memberships {
		out = append(out, memberItem{UserID: m.UserID, Name: users[m.UserID].Name, Role: string(m.Role)})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}
