package v1

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Teams serves POST /v1/teams.
type Teams struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewTeams(s *store.Stores) *Teams {
	return &Teams{stores: s, now: time.Now, newID: uuid.NewString}
}

func (h *Teams) Create(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	name, err := domain.ValidateTeamName(req.Name)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	now := h.now().UTC()
	t := domain.Team{TeamID: h.newID(), Name: name, Status: domain.TeamActive, CreatedBy: c.UserID, CreatedAt: now}
	m := domain.NewMembership(c.UserID, t.TeamID, domain.RoleAdmin, now)
	if err := h.stores.CreateTeamWithAdmin(r.Context(), t, m); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, teamMembership{TeamID: t.TeamID, Name: t.Name, Role: string(domain.RoleAdmin)})
}
