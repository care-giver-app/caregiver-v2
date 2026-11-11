package v1

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// journalNoteBody is the JournalNoteWrite schema.
type journalNoteBody struct {
	At   *time.Time `json:"at"`
	Body string     `json:"body"`
}

// readJournalNote decodes and validates a JournalNoteWrite body, returning the
// time as stored; it writes 400 and returns false when it is not one.
func readJournalNote(w http.ResponseWriter, r *http.Request, now time.Time) (time.Time, string, bool) {
	var b journalNoteBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return time.Time{}, "", false
	}
	if b.At == nil {
		httpx.WriteError(w, http.StatusBadRequest, "at and body are required")
		return time.Time{}, "", false
	}
	at, err := domain.ValidateJournalNote(*b.At, b.Body, now)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return time.Time{}, "", false
	}
	return at, b.Body, true
}

// AddJournalNote serves POST /v1/receivers/{receiverId}/journal-notes: any
// member writes a note about the receiver's day, at the time it is about.
func (h *Home) AddJournalNote(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, ok := loadReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, false) {
		return
	}
	now := h.now().UTC()
	at, body, ok := readJournalNote(w, r, now)
	if !ok {
		return
	}
	n := domain.JournalNote{
		NoteID: h.newID(), ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, At: at, Body: body,
		Author: c.UserID, CreatedAt: now,
	}
	if err := h.stores.JournalNotes.Create(r.Context(), n); err != nil {
		httpx.ServerError(w, r, err, "journal note create failed", "receiver_id", rc.ReceiverID)
		return
	}
	h.writeNote(w, r, http.StatusCreated, n)
}

// noteForCaller loads the note a /v1/journal-notes/{noteId} request is about
// and checks the caller is on its receiver's team: any member may see, edit
// or delete any note. A note about an archived receiver is not found.
func (h *Home) noteForCaller(w http.ResponseWriter, r *http.Request) (*caller, domain.JournalNote, bool) {
	c := requireCaller(w, r)
	if c == nil {
		return nil, domain.JournalNote{}, false
	}
	n, err := h.stores.JournalNotes.Get(r.Context(), r.PathValue("noteId"))
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return nil, domain.JournalNote{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "journal note load failed")
		return nil, domain.JournalNote{}, false
	}
	rc, ok := loadReceiver(w, r, h.stores, n.ReceiverID)
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, false) {
		return nil, domain.JournalNote{}, false
	}
	return c, n, true
}

// ChangeJournalNote serves PUT /v1/journal-notes/{noteId}: Edit journal
// note's Save. The author stays; the caller is recorded as who changed it.
func (h *Home) ChangeJournalNote(w http.ResponseWriter, r *http.Request) {
	c, n, ok := h.noteForCaller(w, r)
	if !ok {
		return
	}
	now := h.now().UTC()
	at, body, ok := readJournalNote(w, r, now)
	if !ok {
		return
	}
	got, err := h.stores.JournalNotes.Put(r.Context(), n.NoteID, at, body, c.UserID, now)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "journal note write failed")
		return
	}
	h.writeNote(w, r, http.StatusOK, got)
}

// DeleteJournalNote serves DELETE /v1/journal-notes/{noteId}. It is gone.
func (h *Home) DeleteJournalNote(w http.ResponseWriter, r *http.Request) {
	_, n, ok := h.noteForCaller(w, r)
	if !ok {
		return
	}
	err := h.stores.JournalNotes.Delete(r.Context(), n.NoteID)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "journal note delete failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Home) writeNote(w http.ResponseWriter, r *http.Request, status int, n domain.JournalNote) {
	names, err := loadEntryNames(r.Context(), h.stores, nil, n.Author, n.UpdatedBy)
	if err != nil {
		httpx.ServerError(w, r, err, "caregiver load failed")
		return
	}
	httpx.WriteJSON(w, status, noteView(n, names.users))
}
