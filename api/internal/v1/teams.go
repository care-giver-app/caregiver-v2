package v1

import (
	"encoding/json"
	"errors"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Teams serves POST /v1/teams and the routes about one care team: its roster,
// closing it, a member's role and removal, and the caller's own notification
// choices for it.
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

// Messages for the contract's named 409s.
const (
	msgLastAdmin        = "a care team always has an admin; promote someone first"
	msgNotLastCaregiver = "only the last caregiver on a care team may close it; anyone else leaves"
)

// teamMember is the TeamMember schema.
type teamMember struct {
	UserID string `json:"user_id"`
	Name   string `json:"name"`
	Role   string `json:"role"`
}

// teamDetail is the TeamDetail schema.
type teamDetail struct {
	TeamID  string       `json:"team_id"`
	Name    string       `json:"name"`
	MyRole  string       `json:"my_role"`
	Members []teamMember `json:"members"`
}

// Get serves GET /v1/teams/{teamId}: the team and everyone on it now, admins
// first, then by name. Any member may read it.
func (h *Teams) Get(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok {
		return
	}
	mine, ok := requireMembership(w, r, h.stores, c, team.TeamID, false)
	if !ok {
		return
	}
	ctx := r.Context()
	ms, err := h.stores.Memberships.ListByTeam(ctx, team.TeamID)
	if err != nil {
		httpx.ServerError(w, r, err, "membership load failed")
		return
	}
	ids := make([]string, 0, len(ms))
	for _, m := range ms {
		ids = append(ids, m.UserID)
	}
	users, err := h.stores.Users.BatchGet(ctx, ids)
	if err != nil {
		httpx.ServerError(w, r, err, "user load failed")
		return
	}
	members := make([]teamMember, 0, len(ms))
	for _, m := range ms {
		members = append(members, teamMember{UserID: m.UserID, Name: caregiverName(users, m.UserID), Role: string(m.Role)})
	}
	sort.Slice(members, func(i, j int) bool {
		a, b := members[i], members[j]
		if (a.Role == string(domain.RoleAdmin)) != (b.Role == string(domain.RoleAdmin)) {
			return a.Role == string(domain.RoleAdmin)
		}
		if an, bn := strings.ToLower(a.Name), strings.ToLower(b.Name); an != bn {
			return an < bn
		}
		return a.UserID < b.UserID
	})
	httpx.WriteJSON(w, http.StatusOK, teamDetail{TeamID: team.TeamID, Name: team.Name, MyRole: string(mine.Role), Members: members})
}

// Close serves POST /v1/teams/{teamId}/close: the last caregiver on the team
// archives it and their membership ends.
func (h *Teams) Close(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, team.TeamID, false) {
		return
	}
	switch err := h.stores.CloseTeam(r.Context(), team.TeamID, c.UserID, h.now().UTC()); {
	case err == nil:
	case errors.Is(err, store.ErrNotLastCaregiver):
		httpx.WriteError(w, http.StatusConflict, msgNotLastCaregiver)
		return
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	default:
		httpx.ServerError(w, r, err, "close failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ChangeRole serves PUT /v1/teams/{teamId}/members/{userId}: an admin makes
// someone on the team an admin or a caregiver. The last admin cannot be made
// a caregiver.
func (h *Teams) ChangeRole(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, team.TeamID, true) {
		return
	}
	var req struct {
		Role domain.Role `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if !req.Role.Valid() {
		httpx.WriteError(w, http.StatusBadRequest, "role must be admin or caregiver")
		return
	}
	ctx := r.Context()
	userID := r.PathValue("userId")
	m, err := h.stores.ChangeRole(ctx, team.TeamID, userID, req.Role)
	switch {
	case err == nil:
	case errors.Is(err, store.ErrLastAdmin):
		httpx.WriteError(w, http.StatusConflict, msgLastAdmin)
		return
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	default:
		httpx.ServerError(w, r, err, "role change failed")
		return
	}
	users, err := h.stores.Users.BatchGet(ctx, []string{userID})
	if err != nil {
		httpx.ServerError(w, r, err, "user load failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, teamMember{UserID: m.UserID, Name: caregiverName(users, m.UserID), Role: string(m.Role)})
}

// RemoveMember serves DELETE /v1/teams/{teamId}/members/{userId}: an admin
// removes anyone, and any member may remove themselves, which is leaving. The
// last admin can do neither to themselves, nor have it done to them.
func (h *Teams) RemoveMember(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok {
		return
	}
	userID := r.PathValue("userId")
	if !requireTeamRole(w, r, h.stores, c, team.TeamID, userID != c.UserID) {
		return
	}
	switch err := h.stores.RemoveMember(r.Context(), team.TeamID, userID); {
	case err == nil:
	case errors.Is(err, store.ErrLastAdmin):
		httpx.WriteError(w, http.StatusConflict, msgLastAdmin)
		return
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	default:
		httpx.ServerError(w, r, err, "remove failed")
		return
	}
	// PR2: free their place on the roster — delete their assignments still
	// ahead on this team and end any coverage schedule naming them today
	// (ADR 0012, Membership, amended in the Team endpoints gate).
	w.WriteHeader(http.StatusNoContent)
}

// notificationChoices is the NotificationChoices schema. Pointers tell a
// required field left out from false.
type notificationChoices struct {
	Reminders        *bool `json:"reminders"`
	RangeAlerts      *bool `json:"range_alerts"`
	GapAlerts        *bool `json:"gap_alerts"`
	UnrecordedAlerts *bool `json:"unrecorded_alerts"`
}

func choicesView(m domain.Membership) notificationChoices {
	return notificationChoices{
		Reminders: &m.NotifyReminders, RangeAlerts: &m.NotifyRangeAlerts,
		GapAlerts: &m.NotifyGapAlerts, UnrecordedAlerts: &m.NotifyUnrecordedAlerts,
	}
}

// MyNotifications serves GET /v1/teams/{teamId}/my-notifications: which kinds
// of notification this team sends the caller.
func (h *Teams) MyNotifications(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok {
		return
	}
	m, ok := requireMembership(w, r, h.stores, c, team.TeamID, false)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, choicesView(m))
}

// ChangeMyNotifications serves PUT /v1/teams/{teamId}/my-notifications. It
// changes the caller's choices only; nobody else on the team is affected.
func (h *Teams) ChangeMyNotifications(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, team.TeamID, false) {
		return
	}
	var req notificationChoices
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Reminders == nil || req.RangeAlerts == nil || req.GapAlerts == nil || req.UnrecordedAlerts == nil {
		httpx.WriteError(w, http.StatusBadRequest, "reminders, range_alerts, gap_alerts and unrecorded_alerts are required")
		return
	}
	m, err := h.stores.Memberships.SetNotifications(r.Context(), c.UserID, team.TeamID, store.NotificationChoices{
		Reminders: *req.Reminders, RangeAlerts: *req.RangeAlerts, GapAlerts: *req.GapAlerts, UnrecordedAlerts: *req.UnrecordedAlerts,
	})
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, choicesView(m))
}
