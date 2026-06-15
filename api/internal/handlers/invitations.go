package handlers

import (
	"net/http"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Invitations struct {
	stores *store.Stores
	now    func() time.Time
}

func NewInvitations(s *store.Stores) *Invitations {
	return &Invitations{stores: s, now: time.Now}
}

type pendingInvitation struct {
	Token         string `json:"token"`
	CareGroupID   string `json:"care_group_id"`
	CareGroupName string `json:"care_group_name"`
	Role          string `json:"role"`
	InvitedBy     string `json:"invited_by"`
}

func (h *Invitations) Mine(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	invs, err := h.stores.Invitations.ListPendingByEmail(ctx, ac.Email)
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	ids := make([]string, 0, len(invs))
	for _, in := range invs {
		ids = append(ids, in.CareGroupID)
	}
	groups, err := h.stores.CareGroups.BatchGet(ctx, ids)
	if err != nil {
		httpx.ServerError(w, r, err, "group load failed")
		return
	}
	out := make([]pendingInvitation, 0, len(invs))
	for _, in := range invs {
		out = append(out, pendingInvitation{
			Token: in.Token, CareGroupID: in.CareGroupID, CareGroupName: groups[in.CareGroupID].Name,
			Role: string(in.Role), InvitedBy: in.InvitedBy,
		})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Invitations) Accept(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	token := r.PathValue("token")

	inv, err := h.stores.Invitations.Get(ctx, token)
	if err != nil {
		httpx.WriteError(w, http.StatusNotFound, "invitation not found")
		return
	}
	if inv.Status == domain.InviteAccepted {
		if _, err := h.stores.Memberships.Get(ctx, ac.UserID, inv.CareGroupID); err == nil {
			h.respondAccepted(w, inv)
			return
		}
	}
	if inv.Status != domain.InvitePending {
		httpx.WriteError(w, http.StatusGone, "invitation no longer valid")
		return
	}
	if inv.Expired(h.now()) {
		httpx.WriteError(w, http.StatusGone, "invitation expired")
		return
	}

	// Admin-role invites are bound to the invited email (higher bar for the higher
	// privilege). Caregiver invites stay token-first (supports Apple private relay).
	if inv.Role == domain.RoleAdmin && domain.NormalizeEmail(ac.Email) != inv.Email {
		httpx.WriteError(w, http.StatusForbidden, "this invitation must be accepted from the invited email")
		return
	}

	mem := domain.Membership{UserID: ac.UserID, CareGroupID: inv.CareGroupID, Role: inv.Role, CreatedAt: h.now().UTC()}
	if err := h.stores.AcceptInvitation(ctx, token, mem); err != nil {
		if _, gErr := h.stores.Memberships.Get(ctx, ac.UserID, inv.CareGroupID); gErr == nil {
			h.respondAccepted(w, inv)
			return
		}
		httpx.WriteError(w, http.StatusGone, "invitation no longer valid")
		return
	}
	h.respondAccepted(w, inv)
}

func (h *Invitations) respondAccepted(w http.ResponseWriter, inv domain.Invitation) {
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"care_group_id": inv.CareGroupID, "role": string(inv.Role),
	})
}
