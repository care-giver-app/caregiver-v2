package v1

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// The 409 messages: the EntryNotInState response, by cause.
const (
	msgTrackerPaused   = "the tracker is paused"
	msgEntryNotInState = "the entry is not in a state this allows; reload it"
)

// newEntryBody is the NewEntry schema.
type newEntryBody struct {
	At              *time.Time     `json:"at"`
	Values          map[string]any `json:"values"`
	Note            string         `json:"note"`
	UnrecordedAlert bool           `json:"unrecorded_alert"`
}

// entryCareBody is the EntryCare schema; the pointer tells occurred_at left
// out from the zero time.
type entryCareBody struct {
	OccurredAt *time.Time     `json:"occurred_at"`
	Values     map[string]any `json:"values"`
	Note       string         `json:"note"`
}

// skipBody is the SkipEntry schema.
type skipBody struct {
	Note string `json:"note"`
}

// AddEntry serves POST /v1/trackers/{trackerId}/entries: Quick log's step for
// a picked tracker, logging ad hoc with at now or earlier and planning a
// one-off scheduled entry with at in the future.
func (h *Home) AddEntry(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	t, rc, ok := loadTracker(w, r, h.stores, r.PathValue("trackerId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, false) {
		return
	}
	if t.Status != domain.TrackerActive {
		httpx.WriteError(w, http.StatusConflict, msgTrackerPaused)
		return
	}
	var b newEntryBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		httpx.ServerError(w, r, err, "receiver time zone invalid", "receiver_id", rc.ReceiverID)
		return
	}
	now := h.now().UTC()
	e, err := domain.NewEntry(domain.NewEntryInput{At: b.At, Values: b.Values, Note: b.Note, UnrecordedAlert: b.UnrecordedAlert},
		t, loc, h.newID(), c.UserID, now)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	created, err := h.stores.Entries.CreateIfAbsent(r.Context(), e)
	if err == nil && !created {
		err = errors.New("entry id collision")
	}
	if err != nil {
		httpx.ServerError(w, r, err, "entry create failed", "tracker_id", t.TrackerID)
		return
	}
	h.writeEntryDetail(w, r, http.StatusCreated, e, t, now)
}

// LogEntry serves POST /v1/entries/{entryId}/log: Log it, on a scheduled or
// unrecorded entry. occurred_at is the run's one time, not the occurrence's.
func (h *Home) LogEntry(w http.ResponseWriter, r *http.Request) {
	c, e, t, ok := h.entryForWrite(w, r)
	if !ok {
		return
	}
	if t.Status != domain.TrackerActive {
		httpx.WriteError(w, http.StatusConflict, msgTrackerPaused)
		return
	}
	if e.State != domain.EntryScheduled {
		httpx.WriteError(w, http.StatusConflict, msgEntryNotInState)
		return
	}
	now := h.now().UTC()
	care, ok := readEntryCare(w, r, t, nil, domain.RequireAll, now)
	if !ok {
		return
	}
	got, err := h.stores.Entries.Log(r.Context(), e.EntryID, care, c.UserID, now)
	h.finishEntryWrite(w, r, got, t, now, err)
}

// SkipEntry serves POST /v1/entries/{entryId}/skip: settle a scheduled or
// unrecorded entry, past or still ahead, as not happening.
func (h *Home) SkipEntry(w http.ResponseWriter, r *http.Request) {
	c, e, t, ok := h.entryForWrite(w, r)
	if !ok {
		return
	}
	if t.Status != domain.TrackerActive {
		httpx.WriteError(w, http.StatusConflict, msgTrackerPaused)
		return
	}
	if e.State != domain.EntryScheduled {
		httpx.WriteError(w, http.StatusConflict, msgEntryNotInState)
		return
	}
	var b skipBody
	// The body only carries an optional note, so an empty one is no note.
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil && !errors.Is(err, io.EOF) {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := domain.ValidateEntryNote(b.Note); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	now := h.now().UTC()
	got, err := h.stores.Entries.Skip(r.Context(), e.EntryID, b.Note, c.UserID, now)
	h.finishEntryWrite(w, r, got, t, now, err)
}

// ChangeEntry serves PUT /v1/entries/{entryId}: Edit entry's Save, on a logged
// or skipped entry, whether or not its tracker has since been paused. Editing
// a skipped entry logs it, so it is checked as a log is; editing a logged one
// may keep values for fields and options since paused or retired.
func (h *Home) ChangeEntry(w http.ResponseWriter, r *http.Request) {
	c, e, t, ok := h.entryForWrite(w, r)
	if !ok {
		return
	}
	var prior map[string]any
	var req domain.Required
	switch e.State {
	case domain.EntryLogged:
		prior, req = e.Values, domain.RequireKept
	case domain.EntrySkipped:
		req = domain.RequireAll
	default:
		httpx.WriteError(w, http.StatusConflict, msgEntryNotInState)
		return
	}
	now := h.now().UTC()
	care, ok := readEntryCare(w, r, t, prior, req, now)
	if !ok {
		return
	}
	got, err := h.stores.Entries.Change(r.Context(), e.EntryID, e.State, care, c.UserID, now)
	h.finishEntryWrite(w, r, got, t, now, err)
}

// DeleteEntry serves DELETE /v1/entries/{entryId}, on a logged or skipped
// entry. One logged ad hoc is removed (204); one that fulfilled a plan goes
// back to waiting with its planned values, and is returned (200).
func (h *Home) DeleteEntry(w http.ResponseWriter, r *http.Request) {
	c, e, t, ok := h.entryForWrite(w, r)
	if !ok {
		return
	}
	if e.State != domain.EntryLogged && e.State != domain.EntrySkipped {
		httpx.WriteError(w, http.StatusConflict, msgEntryNotInState)
		return
	}
	now := h.now().UTC()
	if e.OccurrenceAt != nil {
		got, err := h.stores.Entries.Reopen(r.Context(), e, c.UserID, now)
		h.finishEntryWrite(w, r, got, t, now, err)
		return
	}
	err := h.stores.Entries.DeleteAdHoc(r.Context(), e.EntryID, e.State)
	if !writeEntryErr(w, r, err) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// entryForWrite loads the entry an /v1/entries/{entryId} write is about, and
// its tracker, and checks the caller is on its team: any member may log, skip,
// edit or delete any entry. An entry of an archived receiver is not found.
func (h *Home) entryForWrite(w http.ResponseWriter, r *http.Request) (*caller, domain.Entry, domain.Tracker, bool) {
	c := requireCaller(w, r)
	if c == nil {
		return nil, domain.Entry{}, domain.Tracker{}, false
	}
	e, err := h.stores.Entries.Get(r.Context(), r.PathValue("entryId"))
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return nil, domain.Entry{}, domain.Tracker{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return nil, domain.Entry{}, domain.Tracker{}, false
	}
	t, _, ok := loadTracker(w, r, h.stores, e.TrackerID)
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, false) {
		return nil, domain.Entry{}, domain.Tracker{}, false
	}
	return c, e, t, true
}

// readEntryCare decodes and validates an EntryCare body, writing 400 and
// returning false when it is not one.
func readEntryCare(w http.ResponseWriter, r *http.Request, t domain.Tracker, prior map[string]any, req domain.Required, now time.Time) (domain.EntryCare, bool) {
	var b entryCareBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return domain.EntryCare{}, false
	}
	if b.OccurredAt == nil {
		httpx.WriteError(w, http.StatusBadRequest, "occurred_at and values are required")
		return domain.EntryCare{}, false
	}
	care, err := domain.ValidateEntryCare(domain.EntryCare{OccurredAt: *b.OccurredAt, Values: b.Values, Note: b.Note}, t, prior, req, now)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return domain.EntryCare{}, false
	}
	return care, true
}

// writeEntryErr writes the response for a failed entry write — 404 if it has
// gone, 409 if somebody moved it out of the state the write needed — and
// returns whether err was nil.
func writeEntryErr(w http.ResponseWriter, r *http.Request, err error) bool {
	switch {
	case err == nil:
		return true
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
	case errors.Is(err, store.ErrEntryNotInState):
		httpx.WriteError(w, http.StatusConflict, msgEntryNotInState)
	default:
		httpx.ServerError(w, r, err, "entry write failed")
	}
	return false
}

// finishEntryWrite answers an entry write with the entry as it now stands.
func (h *Home) finishEntryWrite(w http.ResponseWriter, r *http.Request, e domain.Entry, t domain.Tracker, now time.Time, err error) {
	if writeEntryErr(w, r, err) {
		h.writeEntryDetail(w, r, http.StatusOK, e, t, now)
	}
}

func (h *Home) writeEntryDetail(w http.ResponseWriter, r *http.Request, status int, e domain.Entry, t domain.Tracker, now time.Time) {
	d, err := h.entryDetail(r.Context(), e, t, now)
	if err != nil {
		httpx.ServerError(w, r, err, "entry names load failed")
		return
	}
	httpx.WriteJSON(w, status, d)
}
