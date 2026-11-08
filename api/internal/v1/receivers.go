package v1

import (
	"errors"
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Receivers serves GET /v1/teams/{teamId}/receivers. Adding, editing and
// archiving receivers belong to the Team area.
type Receivers struct{ stores *store.Stores }

func NewReceivers(s *store.Stores) *Receivers { return &Receivers{stores: s} }

// careReceiver is the CareReceiver schema.
type careReceiver struct {
	ReceiverID string `json:"receiver_id"`
	TeamID     string `json:"team_id"`
	Name       string `json:"name"`
	TimeZone   string `json:"time_zone"`
}

func (h *Receivers) ListByTeam(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	ctx := r.Context()
	teamID := r.PathValue("teamId")
	team, err := h.stores.Teams.Get(ctx, teamID)
	if errors.Is(err, store.ErrNotFound) || (err == nil && team.Status == domain.TeamArchived) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "team load failed")
		return
	}
	if !requireTeamRole(w, r, h.stores, c, team.TeamID, false) {
		return
	}
	rs, err := h.stores.Receivers.ListActiveByTeam(ctx, team.TeamID)
	if err != nil {
		httpx.ServerError(w, r, err, "receiver load failed")
		return
	}
	out := make([]careReceiver, 0, len(rs))
	for _, rc := range rs {
		out = append(out, careReceiver{ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, Name: rc.Name, TimeZone: rc.TimeZone})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}
