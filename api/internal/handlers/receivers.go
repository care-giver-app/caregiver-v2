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

type Receivers struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewReceivers(s *store.Stores) *Receivers {
	return &Receivers{stores: s, now: time.Now, newID: uuid.NewString}
}

func (h *Receivers) List(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	groupID := r.URL.Query().Get("careGroupId")
	out := []domain.Receiver{}
	if groupID != "" {
		if !httpx.RequireMember(w, ac, groupID) {
			return
		}
		rs, err := h.stores.Receivers.ListByGroup(ctx, groupID)
		if err != nil {
			httpx.ServerError(w, r, err, "list failed")
			return
		}
		out = append(out, rs...)
	} else {
		for gid := range ac.Memberships {
			rs, err := h.stores.Receivers.ListByGroup(ctx, gid)
			if err != nil {
				httpx.ServerError(w, r, err, "list failed")
				return
			}
			out = append(out, rs...)
		}
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Receivers) Create(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	groupID := r.PathValue("careGroupId")
	if !httpx.RequireAdmin(w, ac, groupID) {
		return
	}
	var req struct {
		Name        string `json:"name"`
		DateOfBirth string `json:"date_of_birth"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		httpx.WriteError(w, http.StatusBadRequest, "name is required")
		return
	}
	rec := domain.Receiver{
		ReceiverID: h.newID(), CareGroupID: groupID, Name: strings.TrimSpace(req.Name),
		DateOfBirth: strings.TrimSpace(req.DateOfBirth), CreatedBy: ac.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.Receivers.Put(r.Context(), rec); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, rec)
}

// load fetches a receiver and enforces membership; writes the error response and
// returns ok=false on any failure.
func (h *Receivers) load(w http.ResponseWriter, r *http.Request) (domain.Receiver, *auth.AuthContext, bool) {
	ac := auth.FromContext(r.Context())
	id := r.PathValue("receiverId")
	rec, err := h.stores.Receivers.Get(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) || (err == nil && rec.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "receiver not found")
		return domain.Receiver{}, nil, false
	}
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return domain.Receiver{}, nil, false
	}
	if !httpx.RequireMember(w, ac, rec.CareGroupID) {
		return domain.Receiver{}, nil, false
	}
	return rec, ac, true
}

func (h *Receivers) Get(w http.ResponseWriter, r *http.Request) {
	rec, _, ok := h.load(w, r)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, rec)
}

func (h *Receivers) Update(w http.ResponseWriter, r *http.Request) {
	rec, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, rec.CareGroupID) {
		return
	}
	var req struct {
		Name        *string `json:"name"`
		DateOfBirth *string `json:"date_of_birth"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Name != nil {
		if strings.TrimSpace(*req.Name) == "" {
			httpx.WriteError(w, http.StatusBadRequest, "name cannot be empty")
			return
		}
		rec.Name = strings.TrimSpace(*req.Name)
	}
	if req.DateOfBirth != nil {
		rec.DateOfBirth = strings.TrimSpace(*req.DateOfBirth)
	}
	if err := h.stores.Receivers.Update(r.Context(), rec); err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, rec)
}

func (h *Receivers) Archive(w http.ResponseWriter, r *http.Request) {
	rec, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, rec.CareGroupID) {
		return
	}
	if err := h.stores.Receivers.Archive(r.Context(), rec.ReceiverID); err != nil {
		httpx.ServerError(w, r, err, "archive failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
