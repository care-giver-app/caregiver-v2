package v1

import (
	"encoding/json"
	"errors"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// formerCaregiver names an inviter whose account is gone, closed, or nameless.
const formerCaregiver = "a former caregiver"

// msgInvitationNotValid is the one answer for every unredeemable code, so the
// response never reveals whether it was unknown, expired, used, or revoked.
const msgInvitationNotValid = "invitation not valid"

// Invitations serves GET /v1/me/invitations and POST /v1/invitations/redeem.
type Invitations struct {
	stores *store.Stores
	now    func() time.Time
}

func NewInvitations(s *store.Stores) *Invitations {
	return &Invitations{stores: s, now: time.Now}
}

type invitationForMe struct {
	Code          string `json:"code"`
	TeamID        string `json:"team_id"`
	TeamName      string `json:"team_name"`
	InvitedByName string `json:"invited_by_name"`
	ExpiresAt     string `json:"expires_at"`
}

func (h *Invitations) Mine(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	out := []invitationForMe{}
	if c.Email == "" {
		httpx.WriteJSON(w, http.StatusOK, out)
		return
	}
	ctx := r.Context()
	pending, err := h.stores.Invitations.ListPendingByEmail(ctx, c.Email)
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	now := h.now()
	live := make([]domain.Invitation, 0, len(pending))
	teamIDs := make([]string, 0, len(pending))
	inviterIDs := make([]string, 0, len(pending))
	for _, inv := range pending {
		if inv.Expired(now) {
			continue
		}
		live = append(live, inv)
		teamIDs = append(teamIDs, inv.TeamID)
		inviterIDs = append(inviterIDs, inv.InvitedBy)
	}
	if len(live) == 0 {
		httpx.WriteJSON(w, http.StatusOK, out)
		return
	}
	teams, err := h.stores.Teams.BatchGet(ctx, teamIDs)
	if err != nil {
		httpx.ServerError(w, r, err, "team load failed")
		return
	}
	inviters, err := h.stores.Users.BatchGet(ctx, inviterIDs)
	if err != nil {
		httpx.ServerError(w, r, err, "inviter load failed")
		return
	}
	sort.Slice(live, func(i, j int) bool {
		if live[i].ExpiresAt != live[j].ExpiresAt {
			return live[i].ExpiresAt < live[j].ExpiresAt
		}
		return live[i].Code < live[j].Code
	})
	for _, inv := range live {
		t, ok := teams[inv.TeamID]
		if !ok || t.Status == domain.TeamArchived {
			continue
		}
		out = append(out, invitationForMe{
			Code:          inv.Code,
			TeamID:        t.TeamID,
			TeamName:      t.Name,
			InvitedByName: inviterName(inviters, inv.InvitedBy),
			ExpiresAt:     time.Unix(inv.ExpiresAt, 0).UTC().Format(time.RFC3339),
		})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func inviterName(users map[string]domain.User, id string) string {
	u, ok := users[id]
	if !ok || u.Status == domain.UserClosed || u.Name == "" {
		return formerCaregiver
	}
	return u.Name
}

// Redeem joins the caller to the invitation's team as a caregiver. The code is
// never logged, and the caller's email is never compared with the invitation's.
func (h *Invitations) Redeem(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	var req struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	code := strings.TrimSpace(req.Code)
	if code == "" {
		httpx.WriteError(w, http.StatusBadRequest, "code is required")
		return
	}
	ctx := r.Context()
	now := h.now().UTC()

	inv, err := h.stores.Invitations.Get(ctx, code)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusGone, msgInvitationNotValid)
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	if inv.Status != domain.InvitePending || inv.Expired(now) {
		httpx.WriteError(w, http.StatusGone, msgInvitationNotValid)
		return
	}
	team, err := h.stores.Teams.Get(ctx, inv.TeamID)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusGone, msgInvitationNotValid)
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	if team.Status == domain.TeamArchived {
		httpx.WriteError(w, http.StatusGone, msgInvitationNotValid)
		return
	}
	if _, err := h.stores.Memberships.Get(ctx, c.UserID, team.TeamID); err == nil {
		httpx.WriteError(w, http.StatusConflict, "already a member of this care team")
		return
	} else if !errors.Is(err, store.ErrNotFound) {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}

	m := domain.NewMembership(c.UserID, team.TeamID, domain.RoleCaregiver, now)
	switch err := h.stores.RedeemInvitation(ctx, code, m, now); {
	case err == nil:
	case errors.Is(err, store.ErrInvitationNotValid):
		httpx.WriteError(w, http.StatusGone, msgInvitationNotValid)
		return
	case errors.Is(err, store.ErrAlreadyMember):
		httpx.WriteError(w, http.StatusConflict, "already a member of this care team")
		return
	default:
		httpx.ServerError(w, r, err, "redeem failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, teamMembership{TeamID: team.TeamID, Name: team.Name, Role: string(domain.RoleCaregiver)})
}
