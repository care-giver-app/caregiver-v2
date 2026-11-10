package domain

import (
	"testing"
	"time"
)

func TestOutOfRangeValues(t *testing.T) {
	at := time.Date(2026, 11, 8, 9, 0, 0, 0, time.UTC)
	bp := Tracker{Fields: []Field{
		{FieldID: "sys", Type: FieldNumber, Status: FieldActive, Range: &Range{Low: fp(90), High: fp(140)}},
		{FieldID: "dia", Type: FieldNumber, Status: FieldActive, Range: &Range{High: fp(90)}},
		{FieldID: "pulse", Type: FieldNumber, Status: FieldActive},
		{FieldID: "old", Type: FieldNumber, Status: FieldPaused, Range: &Range{High: fp(1)}},
		{FieldID: "note", Type: FieldText, Status: FieldActive},
	}}
	logged := func(vals map[string]any) Entry {
		return Entry{State: EntryLogged, OccurredAt: &at, Values: vals}
	}
	cases := []struct {
		name string
		e    Entry
		want []string
	}{
		{"all in range", logged(map[string]any{"sys": 120.0, "dia": 80.0, "pulse": 200.0}), nil},
		{"bounds are inclusive", logged(map[string]any{"sys": 140.0, "dia": 90.0}), nil},
		{"both out, in field order", logged(map[string]any{"dia": 95.0, "sys": 80.0}), []string{"sys", "dia"}},
		{"open low bound", logged(map[string]any{"dia": -5.0}), nil},
		{"integer values", logged(map[string]any{"sys": 150}), []string{"sys"}},
		{"paused field and no-range field ignored", logged(map[string]any{"old": 5.0, "pulse": 999.0}), nil},
		{"missing and non-number values ignored", logged(map[string]any{"sys": "high", "note": "x"}), nil},
		{"scheduled entry has no reading", Entry{State: EntryScheduled, Values: map[string]any{"sys": 200.0}}, nil},
		{"skipped entry has no reading", Entry{State: EntrySkipped, Values: map[string]any{"sys": 200.0}}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := OutOfRangeValues(bp, c.e)
			if len(got) != len(c.want) {
				t.Fatalf("got %+v, want fields %v", got, c.want)
			}
			for i, f := range c.want {
				if got[i].FieldID != f {
					t.Fatalf("item %d: got %q, want %q", i, got[i].FieldID, f)
				}
			}
		})
	}
	got := OutOfRangeValues(bp, logged(map[string]any{"sys": 150.0}))
	if got[0].Value != 150 || *got[0].Range.High != 140 || *got[0].Range.Low != 90 {
		t.Fatalf("value and range: %+v", got[0])
	}
}
