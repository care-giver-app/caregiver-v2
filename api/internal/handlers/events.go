package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Events struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewEvents(s *store.Stores) *Events {
	return &Events{stores: s, now: time.Now, newID: uuid.NewString}
}

// eventView wraps a stored event with the computed breaches for the response.
type eventView struct {
	domain.Event
	Breaches []domain.Breach `json:"breaches,omitempty"`
}

type eventWrite struct {
	OccurredAt *time.Time     `json:"occurred_at"`
	Values     map[string]any `json:"values"`
	Note       string         `json:"note"`
}

// trackerForRequest loads the tracker named in the path and enforces membership.
func (h *Events) trackerForRequest(w http.ResponseWriter, r *http.Request) (domain.Tracker, *auth.AuthContext, bool) {
	ac := auth.FromContext(r.Context())
	tr, err := h.stores.Trackers.Get(r.Context(), r.PathValue("trackerId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && tr.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "tracker not found")
		return domain.Tracker{}, nil, false
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return domain.Tracker{}, nil, false
	}
	if !httpx.RequireMember(w, ac, tr.CareGroupID) {
		return domain.Tracker{}, nil, false
	}
	return tr, ac, true
}

func (h *Events) Create(w http.ResponseWriter, r *http.Request) {
	tr, ac, ok := h.trackerForRequest(w, r)
	if !ok {
		return
	}
	var req eventWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Values == nil {
		httpx.WriteError(w, http.StatusBadRequest, "values are required")
		return
	}
	if err := domain.ValidateValues(tr.Fields, req.Values); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	occurred := h.now().UTC()
	if req.OccurredAt != nil {
		occurred = req.OccurredAt.UTC()
	}
	e := domain.Event{
		TrackerID: tr.TrackerID, EventID: h.newID(), CareGroupID: tr.CareGroupID, ReceiverID: tr.ReceiverID,
		Values: req.Values, Note: req.Note, OccurredAt: occurred, LoggedBy: ac.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.Events.Put(r.Context(), e); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "log failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
}

func (h *Events) List(w http.ResponseWriter, r *http.Request) {
	tr, _, ok := h.trackerForRequest(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	limit := int32(50)
	if l := q.Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 100 {
			limit = int32(n)
		}
	}
	var from, to *time.Time
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
	events, next, err := h.stores.Events.ListByTracker(r.Context(), tr.TrackerID, limit, q.Get("cursor"), from, to)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "list failed")
		return
	}
	items := make([]eventView, 0, len(events))
	for _, e := range events {
		items = append(items, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": next})
}

// loadEvent resolves the tracker (for authz + fields) and the addressed event.
func (h *Events) loadEvent(w http.ResponseWriter, r *http.Request) (domain.Tracker, domain.Event, bool) {
	tr, _, ok := h.trackerForRequest(w, r)
	if !ok {
		return domain.Tracker{}, domain.Event{}, false
	}
	e, err := h.stores.Events.Get(r.Context(), tr.TrackerID, r.PathValue("eventId"))
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "event not found")
		return domain.Tracker{}, domain.Event{}, false
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return domain.Tracker{}, domain.Event{}, false
	}
	return tr, e, true
}

func (h *Events) Get(w http.ResponseWriter, r *http.Request) {
	tr, e, ok := h.loadEvent(w, r)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
}

func (h *Events) Update(w http.ResponseWriter, r *http.Request) {
	tr, e, ok := h.loadEvent(w, r)
	if !ok {
		return
	}
	var req eventWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Values == nil {
		httpx.WriteError(w, http.StatusBadRequest, "values are required")
		return
	}
	if err := domain.ValidateValues(tr.Fields, req.Values); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	e.Values = req.Values
	e.Note = req.Note
	if req.OccurredAt != nil {
		e.OccurredAt = req.OccurredAt.UTC()
	}
	if err := h.stores.Events.Update(r.Context(), e); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
}

func (h *Events) Delete(w http.ResponseWriter, r *http.Request) {
	tr, e, ok := h.loadEvent(w, r)
	if !ok {
		return
	}
	if err := h.stores.Events.Delete(r.Context(), tr.TrackerID, e.EventID); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "delete failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
