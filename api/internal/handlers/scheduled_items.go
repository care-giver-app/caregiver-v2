package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type ScheduledItems struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewScheduledItems(s *store.Stores) *ScheduledItems {
	return &ScheduledItems{stores: s, now: time.Now, newID: uuid.NewString}
}

type scheduledItemWrite struct {
	ScheduledFor *time.Time     `json:"scheduled_for"`
	Values       map[string]any `json:"values"`
	Note         string         `json:"note"`
}

func parseListParams(q url.Values) (limit int32, from, to *time.Time, cursor string) {
	limit = 50
	if l := q.Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 100 {
			limit = int32(n)
		}
	}
	if f := q.Get("from"); f != "" {
		if ts, err := time.Parse(time.RFC3339, f); err == nil {
			from = &ts
		}
	}
	if tt := q.Get("to"); tt != "" {
		if ts, err := time.Parse(time.RFC3339, tt); err == nil {
			to = &ts
		}
	}
	return limit, from, to, q.Get("cursor")
}

// scheduledTrackerForRequest loads the tracker named in the path and enforces
// membership.
func (h *ScheduledItems) scheduledTrackerForRequest(w http.ResponseWriter, r *http.Request) (domain.Tracker, *auth.AuthContext, bool) {
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

func (h *ScheduledItems) Create(w http.ResponseWriter, r *http.Request) {
	tr, ac, ok := h.scheduledTrackerForRequest(w, r)
	if !ok {
		return
	}
	if tr.Kind != domain.KindScheduled {
		httpx.WriteError(w, http.StatusBadRequest, "tracker is not a scheduled tracker")
		return
	}
	req, values, ok := decodeScheduledItem(w, r, tr)
	if !ok {
		return
	}
	si := domain.ScheduledItem{
		ScheduledItemID: h.newID(), TrackerID: tr.TrackerID, CareGroupID: tr.CareGroupID, ReceiverID: tr.ReceiverID,
		Values: values, Note: req.Note, ScheduledFor: req.ScheduledFor.UTC(), CreatedBy: ac.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.ScheduledItems.Put(r.Context(), si); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, si)
}

// decodeScheduledItem decodes + validates a write body against a tracker's fields.
func decodeScheduledItem(w http.ResponseWriter, r *http.Request, tr domain.Tracker) (scheduledItemWrite, map[string]any, bool) {
	var req scheduledItemWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return req, nil, false
	}
	if req.ScheduledFor == nil {
		httpx.WriteError(w, http.StatusBadRequest, "scheduled_for is required")
		return req, nil, false
	}
	values := req.Values
	if values == nil {
		values = map[string]any{}
	}
	if err := domain.ValidateValues(tr.Fields, values); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return req, nil, false
	}
	return req, values, true
}

func (h *ScheduledItems) List(w http.ResponseWriter, r *http.Request) {
	tr, _, ok := h.scheduledTrackerForRequest(w, r)
	if !ok {
		return
	}
	limit, from, to, cursor := parseListParams(r.URL.Query())
	items, next, err := h.stores.ScheduledItems.ListByTracker(r.Context(), tr.TrackerID, limit, cursor, from, to)
	if err != nil {
		httpx.ServerError(w, r, err, "list failed")
		return
	}
	writeItems(w, items, next)
}

func (h *ScheduledItems) ListByReceiver(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	rec, err := h.stores.Receivers.Get(r.Context(), r.PathValue("receiverId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && rec.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "receiver not found")
		return
	}
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	if !httpx.RequireMember(w, ac, rec.CareGroupID) {
		return
	}
	limit, from, to, cursor := parseListParams(r.URL.Query())
	items, next, err := h.stores.ScheduledItems.ListByReceiver(r.Context(), rec.ReceiverID, limit, cursor, from, to)
	if err != nil {
		httpx.ServerError(w, r, err, "list failed")
		return
	}
	writeItems(w, items, next)
}

func writeItems(w http.ResponseWriter, items []domain.ScheduledItem, next string) {
	if items == nil {
		items = []domain.ScheduledItem{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": next})
}

// loadScheduledItem resolves the addressed item and enforces membership off its
// denormalized care_group_id.
func (h *ScheduledItems) loadScheduledItem(w http.ResponseWriter, r *http.Request) (domain.ScheduledItem, bool) {
	ac := auth.FromContext(r.Context())
	si, err := h.stores.ScheduledItems.Get(r.Context(), r.PathValue("scheduledItemId"))
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "scheduled item not found")
		return domain.ScheduledItem{}, false
	}
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return domain.ScheduledItem{}, false
	}
	if !httpx.RequireMember(w, ac, si.CareGroupID) {
		return domain.ScheduledItem{}, false
	}
	return si, true
}

func (h *ScheduledItems) Get(w http.ResponseWriter, r *http.Request) {
	si, ok := h.loadScheduledItem(w, r)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, si)
}

func (h *ScheduledItems) Update(w http.ResponseWriter, r *http.Request) {
	si, ok := h.loadScheduledItem(w, r)
	if !ok {
		return
	}
	tr, err := h.stores.Trackers.Get(r.Context(), si.TrackerID)
	if err != nil {
		httpx.ServerError(w, r, err, "lookup failed")
		return
	}
	req, values, ok := decodeScheduledItem(w, r, tr)
	if !ok {
		return
	}
	si.Values = values
	si.Note = req.Note
	si.ScheduledFor = req.ScheduledFor.UTC()
	if err := h.stores.ScheduledItems.Update(r.Context(), si); err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, si)
}

func (h *ScheduledItems) Delete(w http.ResponseWriter, r *http.Request) {
	si, ok := h.loadScheduledItem(w, r)
	if !ok {
		return
	}
	if err := h.stores.ScheduledItems.Delete(r.Context(), si.ScheduledItemID); err != nil {
		httpx.ServerError(w, r, err, "delete failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
