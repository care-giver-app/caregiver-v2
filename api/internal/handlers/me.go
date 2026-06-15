package handlers

import (
	"net/http"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Me struct{ stores *store.Stores }

func NewMe(s *store.Stores) *Me { return &Me{stores: s} }

type meUser struct {
	UserID    string `json:"user_id"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	CreatedAt string `json:"created_at"`
}
type meMembership struct {
	CareGroupID string `json:"care_group_id"`
	Name        string `json:"name"`
	Role        string `json:"role"`
}
type meResponse struct {
	User        meUser         `json:"user"`
	Memberships []meMembership `json:"memberships"`
}

func (h *Me) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	u, err := h.stores.Users.Get(ctx, ac.UserID)
	if err != nil {
		httpx.ServerError(w, r, err, "user load failed")
		return
	}
	ids := make([]string, 0, len(ac.Memberships))
	for id := range ac.Memberships {
		ids = append(ids, id)
	}
	groups, err := h.stores.CareGroups.BatchGet(ctx, ids)
	if err != nil {
		httpx.ServerError(w, r, err, "group load failed")
		return
	}
	resp := meResponse{
		User:        meUser{UserID: u.UserID, Email: u.Email, Name: u.Name, CreatedAt: u.CreatedAt.UTC().Format(time.RFC3339)},
		Memberships: make([]meMembership, 0, len(ac.Memberships)),
	}
	for id, role := range ac.Memberships {
		resp.Memberships = append(resp.Memberships, meMembership{CareGroupID: id, Name: groups[id].Name, Role: string(role)})
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}
