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

type Trackers struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewTrackers(s *store.Stores) *Trackers {
	return &Trackers{stores: s, now: time.Now, newID: uuid.NewString}
}

type trackerWrite struct {
	Name   string             `json:"name"`
	Kind   domain.TrackerKind `json:"kind"`
	Icon   string             `json:"icon"`
	Color  string             `json:"color"`
	Fields []domain.Field     `json:"fields"`
}

// validFields checks the schema definition itself (not event values).
func validFields(fields []domain.Field) bool {
	seen := map[string]bool{}
	for _, f := range fields {
		if f.Key == "" || f.Label == "" || !f.Type.Valid() || seen[f.Key] {
			return false
		}
		if f.Type == domain.FieldEnum && len(f.Options) == 0 {
			return false
		}
		seen[f.Key] = true
	}
	return true
}

func (h *Trackers) ListByReceiver(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	recv, err := h.stores.Receivers.Get(r.Context(), r.PathValue("receiverId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && recv.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "receiver not found")
		return
	}
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	if !httpx.RequireMember(w, ac, recv.CareGroupID) {
		return
	}
	list, err := h.stores.Trackers.ListByReceiver(r.Context(), recv.ReceiverID)
	if err != nil {
		httpx.ServerError(w, r, err, "list failed")
		return
	}
	if list == nil {
		list = []domain.Tracker{}
	}
	httpx.WriteJSON(w, http.StatusOK, list)
}

func (h *Trackers) Create(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	recv, err := h.stores.Receivers.Get(r.Context(), r.PathValue("receiverId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && recv.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "receiver not found")
		return
	}
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	if !httpx.RequireAdmin(w, ac, recv.CareGroupID) {
		return
	}
	var req trackerWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if strings.TrimSpace(req.Name) == "" || !req.Kind.Valid() || !validFields(req.Fields) {
		httpx.WriteError(w, http.StatusBadRequest, "name, a valid kind, and valid fields are required")
		return
	}
	tr := domain.Tracker{
		TrackerID: h.newID(), ReceiverID: recv.ReceiverID, CareGroupID: recv.CareGroupID,
		Name: strings.TrimSpace(req.Name), Kind: req.Kind, Icon: req.Icon, Color: req.Color,
		Fields: req.Fields, CreatedBy: ac.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.Trackers.Put(r.Context(), tr); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, tr)
}

func (h *Trackers) load(w http.ResponseWriter, r *http.Request) (domain.Tracker, *auth.AuthContext, bool) {
	ac := auth.FromContext(r.Context())
	tr, err := h.stores.Trackers.Get(r.Context(), r.PathValue("trackerId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && tr.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "tracker not found")
		return domain.Tracker{}, nil, false
	}
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return domain.Tracker{}, nil, false
	}
	if !httpx.RequireMember(w, ac, tr.CareGroupID) {
		return domain.Tracker{}, nil, false
	}
	return tr, ac, true
}

func (h *Trackers) Get(w http.ResponseWriter, r *http.Request) {
	tr, _, ok := h.load(w, r)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, tr)
}

func (h *Trackers) Update(w http.ResponseWriter, r *http.Request) {
	tr, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, tr.CareGroupID) {
		return
	}
	var req trackerWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if strings.TrimSpace(req.Name) == "" || !req.Kind.Valid() || !validFields(req.Fields) {
		httpx.WriteError(w, http.StatusBadRequest, "name, a valid kind, and valid fields are required")
		return
	}
	tr.Name, tr.Kind, tr.Icon, tr.Color, tr.Fields = strings.TrimSpace(req.Name), req.Kind, req.Icon, req.Color, req.Fields
	if err := h.stores.Trackers.Update(r.Context(), tr); err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, tr)
}

func (h *Trackers) Archive(w http.ResponseWriter, r *http.Request) {
	tr, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, tr.CareGroupID) {
		return
	}
	if err := h.stores.Trackers.Archive(r.Context(), tr.TrackerID); err != nil {
		httpx.ServerError(w, r, err, "archive failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
