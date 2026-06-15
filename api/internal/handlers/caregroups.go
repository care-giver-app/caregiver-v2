package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type CareGroups struct {
	stores    *store.Stores
	now       func() time.Time
	newID     func() string
	newToken  func() (string, error)
	inviteTTL time.Duration
}

func NewCareGroups(s *store.Stores) *CareGroups {
	return &CareGroups{
		stores:    s,
		now:       time.Now,
		newID:     uuid.NewString,
		newToken:  domain.NewInviteToken,
		inviteTTL: 14 * 24 * time.Hour,
	}
}

func (h *CareGroups) Create(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		httpx.WriteError(w, http.StatusBadRequest, "name is required")
		return
	}
	now := h.now().UTC()
	g := domain.CareGroup{CareGroupID: h.newID(), Name: strings.TrimSpace(req.Name), CreatedBy: ac.UserID, CreatedAt: now}
	m := domain.Membership{UserID: ac.UserID, CareGroupID: g.CareGroupID, Role: domain.RoleAdmin, CreatedAt: now}
	if err := h.stores.CreateCareGroupWithAdmin(r.Context(), g, m); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, map[string]any{
		"care_group_id": g.CareGroupID, "name": g.Name, "role": string(domain.RoleAdmin),
	})
}

func (h *CareGroups) CreateInvitation(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	groupID := r.PathValue("careGroupId")
	if !httpx.RequireAdmin(w, ac, groupID) {
		return
	}
	var req struct {
		Email string      `json:"email"`
		Role  domain.Role `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	email := domain.NormalizeEmail(req.Email)
	if email == "" || !req.Role.Valid() {
		httpx.WriteError(w, http.StatusBadRequest, "email and a valid role are required")
		return
	}
	ctx := r.Context()

	pending, err := h.stores.Invitations.ListPendingByEmail(ctx, email)
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	for _, p := range pending {
		if p.CareGroupID == groupID {
			httpx.WriteError(w, http.StatusConflict, "an invite is already pending for this email")
			return
		}
	}
	u, uErr := h.stores.Users.GetByEmail(ctx, email)
	if uErr != nil && !errors.Is(uErr, store.ErrNotFound) {
		httpx.ServerError(w, r, uErr, "lookup failed")
		return
	}
	if uErr == nil {
		_, mErr := h.stores.Memberships.Get(ctx, u.UserID, groupID)
		if mErr != nil && !errors.Is(mErr, store.ErrNotFound) {
			httpx.ServerError(w, r, mErr, "lookup failed")
			return
		}
		if mErr == nil {
			httpx.WriteError(w, http.StatusConflict, "already a member")
			return
		}
	}

	token, err := h.newToken()
	if err != nil {
		httpx.ServerError(w, r, err, "token generation failed")
		return
	}
	expiresAt := h.now().Add(h.inviteTTL).UTC()
	inv := domain.Invitation{
		Token: token, CareGroupID: groupID, Email: email, Role: req.Role,
		Status: domain.InvitePending, InvitedBy: ac.UserID, CreatedAt: h.now().UTC(), ExpiresAt: expiresAt.Unix(),
	}
	if err := h.stores.Invitations.Create(ctx, inv); err != nil {
		httpx.ServerError(w, r, err, "create invite failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, map[string]any{
		"token": token, "email": email, "role": string(req.Role),
		"expires_at": expiresAt.Format(time.RFC3339),
	})
}

func (h *CareGroups) RevokeInvitation(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	groupID := r.PathValue("careGroupId")
	if !httpx.RequireAdmin(w, ac, groupID) {
		return
	}
	token := r.PathValue("token")
	inv, err := h.stores.Invitations.Get(r.Context(), token)
	if err != nil || inv.CareGroupID != groupID {
		httpx.WriteError(w, http.StatusNotFound, "invitation not found")
		return
	}
	if err := h.stores.Invitations.Revoke(r.Context(), token); err != nil {
		httpx.WriteError(w, http.StatusNotFound, "invitation not pending")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
