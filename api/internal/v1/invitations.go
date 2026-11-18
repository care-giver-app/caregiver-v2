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

// formerCaregiver names a caregiver whose account is gone, closed, or nameless.
const formerCaregiver = "a former caregiver"

// msgInvitationNotValid is the one answer for every unredeemable code, so the
// response never reveals whether it was unknown, expired, used, or revoked.
const msgInvitationNotValid = "invitation not valid"

// Invitations serves GET /v1/me/invitations, POST /v1/invitations/redeem,
// and a team's pending invitations: listing them and inviting a caregiver.
type Invitations struct {
	stores  *store.Stores
	now     func() time.Time
	newCode func() (string, error)
}

func NewInvitations(s *store.Stores) *Invitations {
	return &Invitations{stores: s, now: time.Now, newCode: domain.NewInviteCode}
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
			InvitedByName: caregiverName(inviters, inv.InvitedBy),
			ExpiresAt:     time.Unix(inv.ExpiresAt, 0).UTC().Format(time.RFC3339),
		})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func caregiverName(users map[string]domain.User, id string) string {
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

// msgInviteeAlreadyMember is the InviteeAlreadyMember 409.
const msgInviteeAlreadyMember = "that address already belongs to someone on this care team"

// teamInvitation is the TeamInvitation schema.
type teamInvitation struct {
	Code          string `json:"code"`
	Email         string `json:"email"`
	InvitedByName string `json:"invited_by_name"`
	CreatedAt     string `json:"created_at"`
	ExpiresAt     string `json:"expires_at"`
}

func teamInvitationView(inv domain.Invitation, inviterName string) teamInvitation {
	return teamInvitation{
		Code: inv.Code, Email: inv.Email, InvitedByName: inviterName,
		CreatedAt: apiTime(inv.CreatedAt), ExpiresAt: apiTime(time.Unix(inv.ExpiresAt, 0)),
	}
}

// ListByTeam serves GET /v1/teams/{teamId}/invitations: the team's
// invitations not yet used and not yet expired, newest first. Admins only.
func (h *Invitations) ListByTeam(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, team.TeamID, true) {
		return
	}
	ctx := r.Context()
	pending, err := h.stores.Invitations.ListPendingByTeam(ctx, team.TeamID)
	if err != nil {
		httpx.ServerError(w, r, err, "invitation load failed")
		return
	}
	now := h.now()
	live := make([]domain.Invitation, 0, len(pending))
	inviterIDs := make([]string, 0, len(pending))
	for _, inv := range pending {
		if inv.Expired(now) {
			continue
		}
		live = append(live, inv)
		inviterIDs = append(inviterIDs, inv.InvitedBy)
	}
	inviters, err := h.stores.Users.BatchGet(ctx, inviterIDs)
	if err != nil {
		httpx.ServerError(w, r, err, "inviter load failed")
		return
	}
	sort.Slice(live, func(i, j int) bool {
		if !live[i].CreatedAt.Equal(live[j].CreatedAt) {
			return live[i].CreatedAt.After(live[j].CreatedAt)
		}
		return live[i].Code < live[j].Code
	})
	out := make([]teamInvitation, 0, len(live))
	for _, inv := range live {
		out = append(out, teamInvitationView(inv, caregiverName(inviters, inv.InvitedBy)))
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// Create serves POST /v1/teams/{teamId}/invitations: an admin invites an
// address, which joins as a caregiver, and copies the code returned. It is
// refused for an address that belongs to someone already on the team. A
// second invitation to an address already invited is allowed: the PRD expects
// two sent in confusion.
func (h *Invitations) Create(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, team.TeamID, true) {
		return
	}
	var req struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	email, err := domain.ValidateInviteEmail(req.Email)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	ctx := r.Context()
	members, err := h.stores.Memberships.ListByTeam(ctx, team.TeamID)
	if err != nil {
		httpx.ServerError(w, r, err, "membership load failed")
		return
	}
	ids := make([]string, 0, len(members))
	for _, m := range members {
		ids = append(ids, m.UserID)
	}
	users, err := h.stores.Users.BatchGet(ctx, ids)
	if err != nil {
		httpx.ServerError(w, r, err, "user load failed")
		return
	}
	for _, u := range users {
		if u.Email != "" && domain.NormalizeEmail(u.Email) == email {
			httpx.WriteError(w, http.StatusConflict, msgInviteeAlreadyMember)
			return
		}
	}
	code, err := h.newCode()
	if err != nil {
		httpx.ServerError(w, r, err, "code generation failed")
		return
	}
	now := h.now().UTC()
	inv := domain.Invitation{
		Code: code, TeamID: team.TeamID, Email: email, Status: domain.InvitePending, InvitedBy: c.UserID,
		CreatedAt: now, ExpiresAt: now.Add(domain.InvitationTTL).Unix(),
	}
	if err := h.stores.Invitations.Create(ctx, inv); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	inviter := c.Name
	if inviter == "" {
		inviter = formerCaregiver
	}
	httpx.WriteJSON(w, http.StatusCreated, teamInvitationView(inv, inviter))
}
