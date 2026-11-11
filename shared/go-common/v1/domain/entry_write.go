package domain

import (
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"
)

// ErrInvalidEntry is wrapped by every entry validation error, so a handler can
// map them all to 400 with errors.Is and show err.Error().
var ErrInvalidEntry = errors.New("invalid entry")

// ErrInvalidJournalNote is wrapped by every journal note validation error.
var ErrInvalidJournalNote = errors.New("invalid journal note")

func invalidEntry(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalidEntry, fmt.Sprintf(format, args...))
}

func invalidNote(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalidJournalNote, fmt.Sprintf(format, args...))
}

const (
	// MaxEntryNoteLength bounds an entry's note, in characters.
	MaxEntryNoteLength = 2000
	// MaxTextValueLength bounds a text field's value, in characters.
	MaxTextValueLength = 2000
	// MaxJournalNoteLength bounds a journal note's body, in characters.
	MaxJournalNoteLength = 5000
	// ClockSkew is how far ahead of the server's clock a time that may not be
	// in the future is still taken as now: a phone a little fast saying "now"
	// is not planning anything. Such a time is recorded as now.
	ClockSkew = time.Minute
)

// Required says which of a tracker's required active fields a values map must
// answer.
type Required int

const (
	// RequireNone is for planning: a reading nobody has taken yet is left blank.
	RequireNone Required = iota
	// RequireAll is for logging care: every required active field is answered.
	RequireAll
	// RequireKept is for editing a logged entry: a required field it already
	// answers must stay answered, but one it never answered (made required, or
	// added, after it was logged) need not be filled in to correct something
	// else.
	RequireKept
)

// ValidateEntryValues checks values against tracker t. They are keyed by
// field_id and every one must be of its field's kind. Only active fields and
// active options are accepted, except that prior — the entry's values before
// this write, nil for new care — may keep a value it already holds for a field
// paused since, and options of a field retired since that it already chose.
// req says which required active fields must be answered: present, a text not
// blank, a choice with at least one option.
func ValidateEntryValues(t Tracker, values, prior map[string]any, req Required) error {
	if values == nil {
		return invalidEntry("values is required")
	}
	fields := make(map[string]Field, len(t.Fields))
	for _, f := range t.Fields {
		fields[f.FieldID] = f
	}
	for id, v := range values {
		f, ok := fields[id]
		if !ok {
			return invalidEntry("values names unknown field %q", id)
		}
		held, wasHeld := prior[id]
		if f.Status != FieldActive && !wasHeld {
			return invalidEntry("values names paused field %q", f.Label)
		}
		kept := heldOptions(held)
		allowed := func(o ChoiceOption) bool { return o.Status == OptionActive || kept[o.OptionID] }
		if p := valueProblem(f, v, allowed); p != "" {
			return invalidEntry("value for %q %s", f.Label, p)
		}
	}
	if req == RequireNone {
		return nil
	}
	for _, f := range t.Fields {
		if !f.Required || f.Status != FieldActive {
			continue
		}
		if req == RequireKept && !answered(prior[f.FieldID]) {
			continue
		}
		if !answered(values[f.FieldID]) {
			return invalidEntry("%q is required", f.Label)
		}
	}
	return nil
}

// heldOptions is the option ids a stored choice value names.
func heldOptions(v any) map[string]bool {
	list, _ := v.([]any)
	out := make(map[string]bool, len(list))
	for _, item := range list {
		if id, ok := item.(string); ok {
			out[id] = true
		}
	}
	return out
}

// answered reports whether v answers a field: present, a text not blank, a
// choice naming at least one option.
func answered(v any) bool {
	switch x := v.(type) {
	case nil:
		return false
	case string:
		return strings.TrimSpace(x) != ""
	case []any:
		return len(x) > 0
	}
	return true
}

// ValidateEntryNote checks an entry's note length.
func ValidateEntryNote(note string) error {
	if utf8.RuneCountInString(note) > MaxEntryNoteLength {
		return invalidEntry("note must be at most %d characters", MaxEntryNoteLength)
	}
	return nil
}

// PastTime checks at is not in the future, allowing ClockSkew, and returns it
// no later than now — so a logged entry's timeline_at never runs ahead of the
// clock. what names the time in the error.
func PastTime(at, now time.Time, what string) (time.Time, error) {
	if at.After(now.Add(ClockSkew)) {
		return at, fmt.Errorf("%s must not be in the future", what)
	}
	if at.After(now) {
		return now, nil
	}
	return at, nil
}

// EntryCare is what logging or editing an entry records.
type EntryCare struct {
	OccurredAt time.Time
	Values     map[string]any
	Note       string
}

// ValidateEntryCare checks a log or an edit against tracker t and returns it
// with occurred_at no later than now. prior and req are as for
// ValidateEntryValues.
func ValidateEntryCare(c EntryCare, t Tracker, prior map[string]any, req Required, now time.Time) (EntryCare, error) {
	at, err := PastTime(c.OccurredAt, now, "occurred_at")
	if err != nil {
		return c, invalidEntry("%s", err.Error())
	}
	c.OccurredAt = at.UTC()
	if err := ValidateEntryNote(c.Note); err != nil {
		return c, err
	}
	if err := ValidateEntryValues(t, c.Values, prior, req); err != nil {
		return c, err
	}
	return c, nil
}

// NewEntryInput is Quick log's step for a picked tracker (the NewEntry
// schema). A nil At means now.
type NewEntryInput struct {
	At              *time.Time
	Values          map[string]any
	Note            string
	UnrecordedAlert bool
}

// NewEntry builds the entry Quick log's step for a picked tracker writes, with
// id entryID, by user by, on tracker t of a receiver whose zone is loc. With
// At now or earlier (ClockSkew allowed) it is logged ad hoc and every required
// active field must be answered. With At in the future it is a one-off
// scheduled entry planned by hand — shaped like a generated one, less
// schedule_id and grace_minutes — whose values pre-fill it and may leave out
// what nobody can know ahead; unrecorded_alert is accepted only then.
func NewEntry(in NewEntryInput, t Tracker, loc *time.Location, entryID, by string, now time.Time) (Entry, error) {
	now = now.UTC()
	at := now
	if in.At != nil {
		at = in.At.UTC()
	}
	planning := at.After(now.Add(ClockSkew))
	if in.UnrecordedAlert && !planning {
		return Entry{}, invalidEntry("unrecorded_alert is only for an entry planned for a future time")
	}
	if err := ValidateEntryNote(in.Note); err != nil {
		return Entry{}, err
	}
	req := RequireAll
	if planning {
		req = RequireNone
	}
	if err := ValidateEntryValues(t, in.Values, nil, req); err != nil {
		return Entry{}, err
	}
	e := Entry{
		EntryID: entryID, TrackerID: t.TrackerID, ReceiverID: t.ReceiverID, TeamID: t.TeamID,
		Values: CopyValues(in.Values), Note: in.Note, CreatedBy: by, CreatedAt: now,
	}
	if planning {
		e.State = EntryScheduled
		e.OccurrenceLocal = at.In(loc).Format("2006-01-02T15:04")
		e.OccurrenceAt, e.OpenAt = &at, &at
		e.PlannedValues = CopyValues(in.Values)
		e.UnrecordedAlert = in.UnrecordedAlert
		e.TimelineAt = at
		return e, nil
	}
	if at.After(now) {
		at = now
	}
	e.State = EntryLogged
	e.OccurredAt, e.LoggedBy, e.LoggedAt = &at, by, &now
	e.TimelineAt = at
	return e, nil
}

// CopyValues is a shallow copy of a values map, so an entry's values and
// planned values never share one.
func CopyValues(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// ValidateJournalNote checks a journal note's Save: at is the time it is
// about, never in the future (ClockSkew allowed, and then recorded as now),
// and the body is 1-5000 characters and not blank. It returns at as stored.
func ValidateJournalNote(at time.Time, body string, now time.Time) (time.Time, error) {
	at, err := PastTime(at, now, "at")
	if err != nil {
		return at, invalidNote("%s", err.Error())
	}
	if strings.TrimSpace(body) == "" {
		return at, invalidNote("body is required")
	}
	if utf8.RuneCountInString(body) > MaxJournalNoteLength {
		return at, invalidNote("body must be at most %d characters", MaxJournalNoteLength)
	}
	return at.UTC(), nil
}
