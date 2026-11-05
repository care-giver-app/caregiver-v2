package v1

import (
	"net/http"
	"sort"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Me serves GET /v1/me.
type Me struct{ stores *store.Stores }

func NewMe(s *store.Stores) *Me { return &Me{stores: s} }

type caregiverView struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Name   string `json:"name"`
}

type myAccount struct {
	Caregiver caregiverView    `json:"caregiver"`
	Teams     []teamMembership `json:"teams"`
}

func (h *Me) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	ctx := r.Context()
	ms, err := h.stores.Memberships.ListByUser(ctx, c.UserID)
	if err != nil {
		httpx.ServerError(w, r, err, "membership load failed")
		return
	}
	ids := make([]string, 0, len(ms))
	for _, m := range ms {
		ids = append(ids, m.TeamID)
	}
	teams, err := h.stores.Teams.BatchGet(ctx, ids)
	if err != nil {
		httpx.ServerError(w, r, err, "team load failed")
		return
	}
	sort.Slice(ms, func(i, j int) bool {
		if !ms[i].JoinedAt.Equal(ms[j].JoinedAt) {
			return ms[i].JoinedAt.Before(ms[j].JoinedAt)
		}
		return ms[i].TeamID < ms[j].TeamID
	})
	resp := myAccount{
		Caregiver: caregiverView{UserID: c.UserID, Email: c.Email, Name: c.Name},
		Teams:     make([]teamMembership, 0, len(ms)),
	}
	for _, m := range ms {
		t, ok := teams[m.TeamID]
		if !ok || t.Status == domain.TeamArchived {
			continue
		}
		resp.Teams = append(resp.Teams, teamMembership{TeamID: t.TeamID, Name: t.Name, Role: string(m.Role)})
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}
