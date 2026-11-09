package domain

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func fp(v float64) *float64 { return &v }

func TestValidateTrackerName(t *testing.T) {
	if got, err := ValidateTrackerName("  Blood pressure "); err != nil || got != "Blood pressure" {
		t.Fatalf("got %q err=%v", got, err)
	}
	for _, in := range []string{"", "   ", strings.Repeat("a", 101)} {
		if _, err := ValidateTrackerName(in); !errors.Is(err, ErrInvalidTrackerName) || !errors.Is(err, ErrInvalidTracker) {
			t.Fatalf("%q: want ErrInvalidTrackerName, got %v", in, err)
		}
	}
	if _, err := ValidateTrackerName(strings.Repeat("家", 100)); err != nil {
		t.Fatalf("100 runes: %v", err)
	}
}

func TestValidateColor(t *testing.T) {
	for _, ok := range []string{"#A1b2C3", "#000000"} {
		if err := ValidateColor(ok); err != nil {
			t.Fatalf("%q: %v", ok, err)
		}
	}
	for _, bad := range []string{"", "A1B2C3", "#A1B2C", "#A1B2C3D", "#GGGGGG"} {
		if err := ValidateColor(bad); !errors.Is(err, ErrInvalidColor) {
			t.Fatalf("%q: want ErrInvalidColor, got %v", bad, err)
		}
	}
}

func TestValidateGapHours(t *testing.T) {
	zero, one := 0, 1
	if ValidateGapHours(nil) != nil || ValidateGapHours(&one) != nil {
		t.Fatal("nil and 1 should be valid")
	}
	if err := ValidateGapHours(&zero); !errors.Is(err, ErrInvalidGapHours) {
		t.Fatalf("got %v", err)
	}
}

func TestNewFields_assignsIDs(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	got, err := NewFields([]FieldWrite{
		{Label: " Systolic ", Type: FieldNumber, Unit: "mmHg", Required: true, Range: &Range{Low: fp(90), High: fp(140)}},
		{Label: "Mood", Type: FieldChoice, Options: []OptionWrite{{Label: "Good"}, {Label: "Okay", Status: OptionRetired}}},
		{Label: "Pulse", Type: FieldNumber, Status: FieldPaused, Range: &Range{}},
	}, now)
	if err != nil {
		t.Fatalf("NewFields: %v", err)
	}
	if len(got) != 3 || got[0].Label != "Systolic" || got[0].Status != FieldActive || got[0].FieldID == "" ||
		got[0].Range == nil || *got[0].Range.High != 140 {
		t.Fatalf("field 0: %+v", got[0])
	}
	if got[0].FieldID == got[1].FieldID {
		t.Fatal("field ids must be unique")
	}
	opts := got[1].Options
	if len(opts) != 2 || opts[0].OptionID == "" || opts[0].OptionID == opts[1].OptionID ||
		opts[0].Status != OptionActive || opts[1].Status != OptionRetired {
		t.Fatalf("options: %+v", opts)
	}
	if got[2].PausedAt == nil || !got[2].PausedAt.Equal(now) || got[2].Range != nil {
		t.Fatalf("paused field / empty range: %+v", got[2])
	}
	if f, err := NewFields(nil, now); err != nil || len(f) != 0 {
		t.Fatalf("no fields: %+v err=%v", f, err)
	}
}

func TestNewFields_rejects(t *testing.T) {
	cases := []struct {
		name string
		w    FieldWrite
		want error
	}{
		{"empty label", FieldWrite{Label: "  ", Type: FieldText}, ErrInvalidField},
		{"long label", FieldWrite{Label: strings.Repeat("a", 101), Type: FieldText}, ErrInvalidField},
		{"bad type", FieldWrite{Label: "X", Type: "enum"}, ErrInvalidField},
		{"bad status", FieldWrite{Label: "X", Type: FieldText, Status: "archived"}, ErrInvalidField},
		{"unit on text", FieldWrite{Label: "X", Type: FieldText, Unit: "kg"}, ErrInvalidField},
		{"long unit", FieldWrite{Label: "X", Type: FieldNumber, Unit: strings.Repeat("u", 21)}, ErrInvalidField},
		{"range on boolean", FieldWrite{Label: "X", Type: FieldBoolean, Range: &Range{Low: fp(1)}}, ErrInvalidField},
		{"low above high", FieldWrite{Label: "X", Type: FieldNumber, Range: &Range{Low: fp(5), High: fp(4)}}, ErrInvalidField},
		{"multiple on number", FieldWrite{Label: "X", Type: FieldNumber, Multiple: true}, ErrInvalidField},
		{"options on text", FieldWrite{Label: "X", Type: FieldText, Options: []OptionWrite{{Label: "a"}}}, ErrInvalidField},
		{"option without label", FieldWrite{Label: "X", Type: FieldChoice, Options: []OptionWrite{{Label: " "}}}, ErrInvalidField},
		{"bad option status", FieldWrite{Label: "X", Type: FieldChoice, Options: []OptionWrite{{Label: "a", Status: "gone"}}}, ErrInvalidField},
		{"field id sent", FieldWrite{FieldID: "f1", Label: "X", Type: FieldText}, ErrUnknownField},
		{"option id sent", FieldWrite{Label: "X", Type: FieldChoice, Options: []OptionWrite{{OptionID: "o1", Label: "a"}}}, ErrUnknownOption},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := NewFields([]FieldWrite{c.w}, time.Now())
			if !errors.Is(err, c.want) || !errors.Is(err, ErrInvalidTracker) {
				t.Fatalf("want %v, got %v", c.want, err)
			}
		})
	}
	if _, err := NewFields([]FieldWrite{{Label: "X", Type: FieldNumber, Range: &Range{Low: fp(4), High: fp(4)}}}, time.Now()); err != nil {
		t.Fatalf("low == high is valid: %v", err)
	}
}

func existingFields(pausedAt time.Time) []Field {
	return []Field{
		{FieldID: "sys", Label: "Systolic", Type: FieldNumber, Status: FieldActive, Range: &Range{High: fp(140)}},
		{FieldID: "mood", Label: "Mood", Type: FieldChoice, Status: FieldActive, Options: []ChoiceOption{
			{OptionID: "good", Label: "Good", Status: OptionActive},
			{OptionID: "okay", Label: "Okey", Status: OptionActive},
		}},
		{FieldID: "pulse", Label: "Pulse", Type: FieldNumber, Status: FieldPaused, PausedAt: &pausedAt},
	}
}

func TestApplyFieldChanges(t *testing.T) {
	earlier := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	got, err := ApplyFieldChanges(existingFields(earlier), []FieldWrite{
		{FieldID: "mood", Label: "Mood", Type: FieldChoice, Options: []OptionWrite{
			{OptionID: "okay", Label: "Okay"},
			{OptionID: "good", Label: "Good", Status: OptionRetired},
			{Label: "Bad"},
		}},
		{FieldID: "sys", Label: "Systolic", Type: FieldNumber, Status: FieldPaused},
		{FieldID: "pulse", Label: "Pulse", Type: FieldNumber, Status: FieldPaused},
		{Label: "Note", Type: FieldText},
	}, now)
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if len(got) != 4 || got[0].FieldID != "mood" || got[1].FieldID != "sys" || got[2].FieldID != "pulse" {
		t.Fatalf("order not kept: %+v", got)
	}
	opts := got[0].Options
	if len(opts) != 3 || opts[0].OptionID != "okay" || opts[0].Label != "Okay" || opts[1].Status != OptionRetired ||
		opts[2].OptionID == "" || opts[2].Label != "Bad" {
		t.Fatalf("options: %+v", opts)
	}
	if got[1].PausedAt == nil || !got[1].PausedAt.Equal(now) || got[1].Range != nil {
		t.Fatalf("newly paused: %+v", got[1])
	}
	if got[2].PausedAt == nil || !got[2].PausedAt.Equal(earlier) {
		t.Fatalf("already paused should keep its time: %+v", got[2])
	}
	if got[3].FieldID == "" || got[3].FieldID == "sys" {
		t.Fatalf("new field id: %+v", got[3])
	}

	resumed, err := ApplyFieldChanges(existingFields(earlier), []FieldWrite{
		{FieldID: "sys", Label: "Systolic", Type: FieldNumber},
		{FieldID: "mood", Label: "Mood", Type: FieldChoice, Options: []OptionWrite{{OptionID: "good", Label: "Good"}, {OptionID: "okay", Label: "Okay"}}},
		{FieldID: "pulse", Label: "Pulse", Type: FieldNumber, Status: FieldActive},
	}, now)
	if err != nil || resumed[2].Status != FieldActive || resumed[2].PausedAt != nil {
		t.Fatalf("resume: %+v err=%v", resumed, err)
	}
}

func TestApplyFieldChanges_rejects(t *testing.T) {
	sys := FieldWrite{FieldID: "sys", Label: "Systolic", Type: FieldNumber}
	pulse := FieldWrite{FieldID: "pulse", Label: "Pulse", Type: FieldNumber, Status: FieldPaused}
	mood := func(opts ...OptionWrite) FieldWrite {
		return FieldWrite{FieldID: "mood", Label: "Mood", Type: FieldChoice, Options: opts}
	}
	bothOpts := []OptionWrite{{OptionID: "good", Label: "Good"}, {OptionID: "okay", Label: "Okay"}}
	cases := []struct {
		name string
		ws   []FieldWrite
		want error
	}{
		{"field left out", []FieldWrite{sys, mood(bothOpts...)}, ErrFieldOmitted},
		{"option left out", []FieldWrite{sys, mood(OptionWrite{OptionID: "good", Label: "Good"}), pulse}, ErrOptionOmitted},
		{"type changed", []FieldWrite{{FieldID: "sys", Label: "Systolic", Type: FieldText}, mood(bothOpts...), pulse}, ErrFieldTypeChanged},
		{"answers changed", []FieldWrite{sys, {FieldID: "mood", Label: "Mood", Type: FieldChoice, Multiple: true, Options: bothOpts}, pulse}, ErrFieldAnswersChanged},
		{"unknown field", []FieldWrite{sys, mood(bothOpts...), pulse, {FieldID: "nope", Label: "X", Type: FieldText}}, ErrUnknownField},
		{"field twice", []FieldWrite{sys, sys, mood(bothOpts...), pulse}, ErrUnknownField},
		{"unknown option", []FieldWrite{sys, mood(append(bothOpts, OptionWrite{OptionID: "nope", Label: "X"})...), pulse}, ErrUnknownOption},
		{"option twice", []FieldWrite{sys, mood(append(bothOpts, bothOpts[0])...), pulse}, ErrUnknownOption},
		{"shape on existing", []FieldWrite{{FieldID: "sys", Label: "", Type: FieldNumber}, mood(bothOpts...), pulse}, ErrInvalidField},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := ApplyFieldChanges(existingFields(time.Now()), c.ws, time.Now())
			if !errors.Is(err, c.want) || !errors.Is(err, ErrInvalidTracker) {
				t.Fatalf("want %v, got %v", c.want, err)
			}
		})
	}
}
