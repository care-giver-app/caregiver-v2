package domain

import (
	"errors"
	"strings"
	"testing"
	"time"
)

var writeNow = time.Date(2026, 11, 8, 18, 0, 0, 0, time.UTC)

func entryTracker() Tracker {
	return Tracker{
		TrackerID: "tr", ReceiverID: "r", TeamID: "t", Status: TrackerActive,
		Fields: []Field{
			{FieldID: "sys", Label: "Systolic", Type: FieldNumber, Required: true, Status: FieldActive},
			{FieldID: "mood", Label: "Mood", Type: FieldChoice, Status: FieldActive, Options: []ChoiceOption{
				{OptionID: "ok", Label: "Okay", Status: OptionActive}, {OptionID: "meh", Label: "Meh", Status: OptionRetired},
			}},
			{FieldID: "syms", Label: "Symptoms", Type: FieldChoice, Multiple: true, Status: FieldActive, Options: []ChoiceOption{
				{OptionID: "a", Label: "A", Status: OptionActive}, {OptionID: "b", Label: "B", Status: OptionActive},
			}},
			{FieldID: "txt", Label: "Notes", Type: FieldText, Required: true, Status: FieldActive},
			{FieldID: "ok", Label: "Ate", Type: FieldBoolean, Status: FieldActive},
			{FieldID: "when", Label: "Next", Type: FieldDatetime, Status: FieldActive},
			{FieldID: "pulse", Label: "Pulse", Type: FieldNumber, Required: true, Status: FieldPaused},
		},
	}
}

func TestValidateEntryValues(t *testing.T) {
	tr := entryTracker()
	full := func(extra map[string]any) map[string]any {
		m := map[string]any{"sys": 120.0, "txt": "fine"}
		for k, v := range extra {
			m[k] = v
		}
		return m
	}
	for _, tc := range []struct {
		name   string
		values map[string]any
		prior  map[string]any
		req    Required
		want   string // "" for valid
	}{
		{"all kinds", full(map[string]any{"mood": []any{"ok"}, "syms": []any{"a", "b"}, "ok": true, "when": "2026-12-01T09:00:00Z"}), nil, RequireAll, ""},
		{"nil values", nil, nil, RequireNone, "values is required"},
		{"unknown field", full(map[string]any{"x": 1.0}), nil, RequireAll, `unknown field "x"`},
		{"paused field", full(map[string]any{"pulse": 70.0}), nil, RequireAll, `paused field "Pulse"`},
		{"paused field kept on edit", full(map[string]any{"pulse": 72.0}), map[string]any{"pulse": 70.0}, RequireKept, ""},
		{"retired option", full(map[string]any{"mood": []any{"meh"}}), nil, RequireAll, `retired option "meh"`},
		{"retired option kept on edit", full(map[string]any{"mood": []any{"meh"}}), map[string]any{"mood": []any{"meh"}}, RequireKept, ""},
		{"two answers to one", full(map[string]any{"mood": []any{"ok", "ok"}}), nil, RequireAll, "at most one option"},
		{"option twice", full(map[string]any{"syms": []any{"a", "a"}}), nil, RequireAll, `option "a" twice`},
		{"number as text", map[string]any{"sys": "120", "txt": "x"}, nil, RequireAll, "must be a number"},
		{"text at the limit", full(map[string]any{"txt": strings.Repeat("é", MaxTextValueLength)}), nil, RequireAll, ""},
		{"text too long", full(map[string]any{"txt": strings.Repeat("a", MaxTextValueLength+1)}), nil, RequireAll, "at most 2000 characters"},
		{"null", full(map[string]any{"ok": nil}), nil, RequireAll, "must be true or false"},
		{"bad datetime", full(map[string]any{"when": "tomorrow"}), nil, RequireAll, "date and time"},
		{"choice not a list", full(map[string]any{"mood": "ok"}), nil, RequireAll, "list of option ids"},
		{"required missing on log", map[string]any{"txt": "x"}, nil, RequireAll, `"Systolic" is required`},
		{"required blank text on log", map[string]any{"sys": 1.0, "txt": "  "}, nil, RequireAll, `"Notes" is required`},
		{"required missing when planning", map[string]any{}, nil, RequireNone, ""},
		{"paused required field not asked", map[string]any{"sys": 1.0, "txt": "x"}, nil, RequireAll, ""},
		{"edit keeps a required answer", map[string]any{"txt": "x"}, map[string]any{"sys": 1.0, "txt": "x"}, RequireKept, `"Systolic" is required`},
		{"edit need not add one never answered", map[string]any{"sys": 1.0}, map[string]any{"sys": 1.0}, RequireKept, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := ValidateEntryValues(tr, tc.values, tc.prior, tc.req)
			if tc.want == "" {
				if err != nil {
					t.Fatalf("want valid, got %v", err)
				}
				return
			}
			if !errors.Is(err, ErrInvalidEntry) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("want %q, got %v", tc.want, err)
			}
		})
	}
}

func TestNewEntry(t *testing.T) {
	tr := entryTracker()
	loc, _ := time.LoadLocation("America/Chicago")
	vals := map[string]any{"sys": 120.0, "txt": "fine"}
	at := func(d time.Duration) *time.Time { v := writeNow.Add(d); return &v }

	// Absent at is now: logged ad hoc.
	e, err := NewEntry(NewEntryInput{Values: vals, Note: "n"}, tr, loc, "e1", "u1", writeNow)
	if err != nil {
		t.Fatal(err)
	}
	if e.State != EntryLogged || !e.OccurredAt.Equal(writeNow) || !e.TimelineAt.Equal(writeNow) || e.LoggedBy != "u1" ||
		e.OccurrenceAt != nil || e.OpenAt != nil || e.PlannedValues != nil || e.Note != "n" || e.TeamID != "t" {
		t.Fatalf("ad hoc: %+v", e)
	}
	// Within the clock skew is still now, recorded as now.
	e, err = NewEntry(NewEntryInput{At: at(30 * time.Second), Values: vals}, tr, loc, "e1", "u1", writeNow)
	if err != nil || e.State != EntryLogged || !e.OccurredAt.Equal(writeNow) {
		t.Fatalf("skewed: %v %+v", err, e)
	}
	// Past: logged at that time, required fields asked.
	if _, err := NewEntry(NewEntryInput{At: at(-time.Hour), Values: map[string]any{}}, tr, loc, "e1", "u1", writeNow); err == nil {
		t.Fatal("past log without required fields accepted")
	}
	// unrecorded_alert only with a future time.
	if _, err := NewEntry(NewEntryInput{At: at(-time.Hour), Values: vals, UnrecordedAlert: true}, tr, loc, "e1", "u1", writeNow); !errors.Is(err, ErrInvalidEntry) {
		t.Fatalf("alert on a log: %v", err)
	}
	// Future: a scheduled entry, shaped like a generated one less schedule_id.
	e, err = NewEntry(NewEntryInput{At: at(26 * time.Hour), Values: map[string]any{"txt": "bring list"}, UnrecordedAlert: true}, tr, loc, "e2", "u1", writeNow)
	if err != nil {
		t.Fatal(err)
	}
	when := writeNow.Add(26 * time.Hour)
	if e.State != EntryScheduled || !e.OccurrenceAt.Equal(when) || !e.OpenAt.Equal(when) || !e.TimelineAt.Equal(when) ||
		e.OccurrenceLocal != "2026-11-09T14:00" || !e.UnrecordedAlert || e.PlannedValues["txt"] != "bring list" ||
		e.Values["txt"] != "bring list" || e.ScheduleID != "" || e.OccurredAt != nil || e.LoggedBy != "" || e.CreatedBy != "u1" {
		t.Fatalf("planned: %+v", e)
	}
	// Planning still checks kinds and active fields.
	if _, err := NewEntry(NewEntryInput{At: at(time.Hour), Values: map[string]any{"pulse": 1.0}}, tr, loc, "e2", "u1", writeNow); err == nil {
		t.Fatal("planned a paused field")
	}
	if _, err := NewEntry(NewEntryInput{Values: vals, Note: strings.Repeat("x", MaxEntryNoteLength+1)}, tr, loc, "e1", "u1", writeNow); err == nil {
		t.Fatal("long note accepted")
	}
}

func TestValidateEntryCare(t *testing.T) {
	tr := entryTracker()
	vals := map[string]any{"sys": 120.0, "txt": "fine"}
	c, err := ValidateEntryCare(EntryCare{OccurredAt: writeNow.Add(ClockSkew), Values: vals}, tr, nil, RequireAll, writeNow)
	if err != nil || !c.OccurredAt.Equal(writeNow) {
		t.Fatalf("at the skew: %v %v", err, c.OccurredAt)
	}
	if _, err := ValidateEntryCare(EntryCare{OccurredAt: writeNow.Add(ClockSkew + time.Second), Values: vals}, tr, nil, RequireAll, writeNow); !errors.Is(err, ErrInvalidEntry) {
		t.Fatalf("future occurred_at: %v", err)
	}
}

func TestValidateJournalNote(t *testing.T) {
	if at, err := ValidateJournalNote(writeNow.Add(-time.Hour), "slept well", writeNow); err != nil || !at.Equal(writeNow.Add(-time.Hour)) {
		t.Fatalf("valid: %v", err)
	}
	if at, err := ValidateJournalNote(writeNow.Add(20*time.Second), "x", writeNow); err != nil || !at.Equal(writeNow) {
		t.Fatalf("skewed: %v %v", err, at)
	}
	for name, tc := range map[string]struct {
		at   time.Time
		body string
	}{
		"future": {writeNow.Add(2 * time.Minute), "x"},
		"blank":  {writeNow, "   "},
		"empty":  {writeNow, ""},
		"long":   {writeNow, strings.Repeat("é", MaxJournalNoteLength+1)},
	} {
		if _, err := ValidateJournalNote(tc.at, tc.body, writeNow); !errors.Is(err, ErrInvalidJournalNote) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if _, err := ValidateJournalNote(writeNow, strings.Repeat("é", MaxJournalNoteLength), writeNow); err != nil {
		t.Errorf("5000 characters: %v", err)
	}
}
