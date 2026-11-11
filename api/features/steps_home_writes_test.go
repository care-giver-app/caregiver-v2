package features_test

import (
	"context"
	"fmt"
	"net/http"

	"github.com/cucumber/godog"
)

// Home's writes, driven through the API as a caregiver makes them: Quick log
// logging and planning, Log it and Skip on a waiting occurrence, Edit and
// Delete on an entry, and writing, editing and deleting a journal note.
// Every entry and note the API makes is tracked for cleanup as it is made.

func (w *world) registerHomeWrites(sc *godog.ScenarioContext) {
	sc.Step(`^"([^"]*)" logs "([^"]*)" as of `+when+`$`, w.logsTracker)
	sc.Step(`^"([^"]*)" logs "([^"]*)" as of `+when+` with "([^"]*)" at ([\d.]+)$`, w.logsTrackerWithValue)
	sc.Step(`^"([^"]*)" logs "([^"]*)" as of `+when+`, leaving "([^"]*)" blank$`, w.logsLeavingBlank)
	sc.Step(`^"([^"]*)" plans "([^"]*)" for `+when+`$`, w.plansTracker)
	sc.Step(`^"([^"]*)" plans "([^"]*)" for `+when+`, leaving "([^"]*)" blank$`, w.plansLeavingBlank)

	sc.Step(`^"([^"]*)" logs that entry as of `+when+`$`, w.logsThatEntry)
	sc.Step(`^"([^"]*)" logs that entry as of `+when+` with "([^"]*)" at ([\d.]+)$`, w.logsThatEntryWithValue)
	sc.Step(`^"([^"]*)" skips that entry$`, w.skipsThatEntry)
	sc.Step(`^"([^"]*)" skips that entry, saying "([^"]*)"$`, w.skipsThatEntrySaying)
	sc.Step(`^"([^"]*)" edits that entry, changing "([^"]*)" to ([\d.]+)$`, w.editsEntryValue)
	sc.Step(`^"([^"]*)" edits that entry, saying it happened `+when+`$`, w.editsEntryTime)
	sc.Step(`^"([^"]*)" deletes that entry$`, w.deletesThatEntry)

	sc.Step(`^"([^"]*)" writes a journal note about "([^"]*)" as of `+when+`: "([^"]*)"$`, w.writesNote)
	sc.Step(`^"([^"]*)" edits that note to read "([^"]*)"$`, w.editsNote)
	sc.Step(`^"([^"]*)" deletes that note$`, w.deletesThatNote)

	sc.Step(`^it is the "([^"]*)" entry (logged|skipped) by "([^"]*)", at `+when+`$`, w.entryIsSettledAt)
	sc.Step(`^its "([^"]*)" reads ([\d.]+)$`, w.entryValueReads)
	sc.Step(`^its note says "([^"]*)"$`, w.entryNoteSays)
	sc.Step(`^the entry was last changed by "([^"]*)"$`, w.entryLastChangedByNow)
	sc.Step(`^the note was last changed by "([^"]*)"$`, w.noteLastChangedByNow)
	sc.Step(`^nothing is waiting in Quick log$`, w.nothingWaiting)
}

// ---- Quick log on a picked tracker ------------------------------------------------

// addEntry is Quick log's step for a picked tracker, the run's one time at.
// A new entry becomes "that entry", tracked for cleanup.
func (w *world) addEntry(ctx context.Context, label, tracker, phrase string, values map[string]any) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	t, err := w.tracker(tracker)
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	body := map[string]any{"at": apiTime(at), "values": values}
	if err := w.call(ctx, p, http.MethodPost, "/v1/trackers/"+t.TrackerID+"/entries", body); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		return w.keepEntry(true)
	}
	return nil
}

// keepEntry keeps the Entry detail a write answered with as "that entry",
// tracking it for cleanup when the write made it.
func (w *world) keepEntry(made bool) error {
	d, err := decodeLast[entryDetailView](w)
	if err != nil {
		return err
	}
	if d.Entry.EntryID == "" {
		return w.unexpected("an entry with an id")
	}
	if made {
		w.track(entryKey(w.d.db().names, d.Entry.EntryID))
	}
	w.home.lastEntry, w.home.entry = d.Entry.EntryID, &d
	return nil
}

func (w *world) fieldID(tracker, label string) (string, error) {
	t, err := w.tracker(tracker)
	if err != nil {
		return "", err
	}
	for _, f := range t.Fields {
		if f.Label == label {
			return f.FieldID, nil
		}
	}
	return "", fmt.Errorf("%q has no field %q", tracker, label)
}

func (w *world) logsTracker(ctx context.Context, label, tracker, phrase string) error {
	return w.addEntry(ctx, label, tracker, phrase, map[string]any{})
}

func (w *world) logsTrackerWithValue(ctx context.Context, label, tracker, phrase, field string, v float64) error {
	id, err := w.fieldID(tracker, field)
	if err != nil {
		return err
	}
	return w.addEntry(ctx, label, tracker, phrase, map[string]any{id: v})
}

// logsLeavingBlank leaves the named field out of the values, as a caregiver
// leaving it blank does.
func (w *world) logsLeavingBlank(ctx context.Context, label, tracker, phrase, field string) error {
	if _, err := w.fieldID(tracker, field); err != nil {
		return err
	}
	return w.addEntry(ctx, label, tracker, phrase, map[string]any{})
}

func (w *world) plansTracker(ctx context.Context, label, tracker, phrase string) error {
	return w.addEntry(ctx, label, tracker, phrase, map[string]any{})
}

func (w *world) plansLeavingBlank(ctx context.Context, label, tracker, phrase, field string) error {
	return w.logsLeavingBlank(ctx, label, tracker, phrase, field)
}

// ---- Log it, Skip, Edit and Delete on that entry ----------------------------------

func (w *world) thatEntry() (string, error) {
	if w.home.lastEntry == "" {
		return "", fmt.Errorf("the scenario has no entry to act on")
	}
	return w.home.lastEntry, nil
}

// entryWrite sends one write about that entry as label, keeping the entry it
// answers with.
func (w *world) entryWrite(ctx context.Context, label, method, suffix string, body any) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.thatEntry()
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, method, "/v1/entries/"+id+suffix, body); err != nil {
		return err
	}
	if w.last.status == http.StatusOK {
		return w.keepEntry(false)
	}
	return nil
}

func (w *world) logThatEntry(ctx context.Context, label, phrase string, values map[string]any) error {
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.entryWrite(ctx, label, http.MethodPost, "/log", map[string]any{"occurred_at": apiTime(at), "values": values})
}

func (w *world) logsThatEntry(ctx context.Context, label, phrase string) error {
	return w.logThatEntry(ctx, label, phrase, map[string]any{})
}

func (w *world) logsThatEntryWithValue(ctx context.Context, label, phrase, field string, v float64) error {
	id, err := w.fieldOfThatEntry(field)
	if err != nil {
		return err
	}
	return w.logThatEntry(ctx, label, phrase, map[string]any{id: v})
}

// fieldOfThatEntry finds the field id by label across the scenario's
// trackers: "that entry" was made through the API, so its tracker is known by
// the fields it shares with one the scenario made.
func (w *world) fieldOfThatEntry(label string) (string, error) {
	for _, t := range w.care.trackers {
		for _, f := range t.Fields {
			if f.Label == label {
				return f.FieldID, nil
			}
		}
	}
	return "", fmt.Errorf("no tracker in the scenario has a field %q", label)
}

func (w *world) skipsThatEntry(ctx context.Context, label string) error {
	return w.entryWrite(ctx, label, http.MethodPost, "/skip", map[string]any{})
}

func (w *world) skipsThatEntrySaying(ctx context.Context, label, note string) error {
	return w.entryWrite(ctx, label, http.MethodPost, "/skip", map[string]any{"note": note})
}

// editEntry is Edit entry: the form opens on the entry as it stands, the
// caregiver changes one thing, and saves.
func (w *world) editEntry(ctx context.Context, label string, change func(body map[string]any) error) error {
	if err := w.opensThatEntry(ctx, label); err != nil {
		return err
	}
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	values := d.Entry.Values
	if values == nil {
		values = map[string]any{}
	}
	body := map[string]any{"occurred_at": d.Entry.At, "values": values, "note": d.Entry.Note}
	if err := change(body); err != nil {
		return err
	}
	return w.entryWrite(ctx, label, http.MethodPut, "", body)
}

func (w *world) editsEntryValue(ctx context.Context, label, field string, v float64) error {
	id, err := w.fieldOfThatEntry(field)
	if err != nil {
		return err
	}
	return w.editEntry(ctx, label, func(body map[string]any) error {
		body["values"].(map[string]any)[id] = v
		return nil
	})
}

func (w *world) editsEntryTime(ctx context.Context, label, phrase string) error {
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	return w.editEntry(ctx, label, func(body map[string]any) error {
		body["occurred_at"] = apiTime(at)
		return nil
	})
}

func (w *world) deletesThatEntry(ctx context.Context, label string) error {
	return w.entryWrite(ctx, label, http.MethodDelete, "", nil)
}

// ---- journal notes ----------------------------------------------------------------

func (w *world) writesNote(ctx context.Context, label, receiver, phrase, body string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodPost, "/v1/receivers/"+rc.ReceiverID+"/journal-notes",
		map[string]any{"at": apiTime(at), "body": body}); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		n, err := decodeLast[journalNoteView](w)
		if err != nil {
			return err
		}
		if n.NoteID == "" {
			return w.unexpected("a journal note with an id")
		}
		w.track(journalNoteKey(w.d.db().names, n.NoteID))
		w.home.lastNote, w.home.note = n.NoteID, &n
	}
	return nil
}

// editsNote is Edit journal note: it opens on the note as it stands, and the
// caregiver rewrites what it says.
func (w *world) editsNote(ctx context.Context, label, body string) error {
	if err := w.opensThatNote(ctx, label); err != nil {
		return err
	}
	n, err := w.shownNote()
	if err != nil {
		return err
	}
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodPut, "/v1/journal-notes/"+n.NoteID, map[string]any{"at": n.At, "body": body})
}

func (w *world) deletesThatNote(ctx context.Context, label string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	if w.home.lastNote == "" {
		return fmt.Errorf("the scenario has written no journal note")
	}
	return w.call(ctx, p, http.MethodDelete, "/v1/journal-notes/"+w.home.lastNote, nil)
}

// ---- what Entry detail and Journal note then show ---------------------------------

// entryIsSettledAt checks who settled the entry and the time it sits at,
// without the moment they pressed the button, which is the server's to stamp.
func (w *world) entryIsSettledAt(tracker, state, by, phrase string) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	at, err := w.at(phrase)
	if err != nil {
		return err
	}
	if d.Tracker.Name != tracker || d.Entry.State != state || d.Entry.ByName != by ||
		d.Entry.At != apiTime(at) || d.SettledAt == nil {
		return w.unexpected(fmt.Sprintf("the %q entry %s by %q, at %s", tracker, state, by, apiTime(at)))
	}
	return nil
}

func (w *world) entryValueReads(field string, v float64) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	id, err := w.fieldOfThatEntry(field)
	if err != nil {
		return err
	}
	if got, ok := d.Entry.Values[id].(float64); !ok || got != v {
		return w.unexpected(fmt.Sprintf("the entry's %q to read %v", field, v))
	}
	return nil
}

func (w *world) entryNoteSays(note string) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	if d.Entry.Note != note {
		return w.unexpected(fmt.Sprintf("the entry's note to say %q", note))
	}
	return nil
}

func (w *world) entryLastChangedByNow(by string) error {
	d, err := w.shownEntry()
	if err != nil {
		return err
	}
	if d.UpdatedByName != by || d.UpdatedAt == nil {
		return w.unexpected(fmt.Sprintf("the entry to have been last changed by %q", by))
	}
	return nil
}

func (w *world) noteLastChangedByNow(by string) error {
	n, err := w.shownNote()
	if err != nil {
		return err
	}
	if n.UpdatedByName != by || n.UpdatedAt == nil {
		return w.unexpected(fmt.Sprintf("the note to have been last changed by %q", by))
	}
	return nil
}

func (w *world) nothingWaiting() error {
	if w.last.status != http.StatusOK {
		return w.unexpected("Quick log's waiting occurrences to load (200)")
	}
	if w.home.items == nil || len(w.home.items) != 0 {
		return w.unexpected("nothing to be waiting (an empty list)")
	}
	return nil
}
