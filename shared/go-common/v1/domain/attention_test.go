package domain

import (
	"testing"
	"time"
)

func TestEntry_DisplayState(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	past, future := now.Add(-time.Minute), now.Add(time.Minute)
	cases := []struct {
		name string
		e    Entry
		want EntryState
	}{
		{"logged", Entry{State: EntryLogged, OccurrenceAt: &past}, EntryLogged},
		{"skipped", Entry{State: EntrySkipped, OccurrenceAt: &past}, EntrySkipped},
		{"scheduled past", Entry{State: EntryScheduled, OccurrenceAt: &past}, EntryUnrecorded},
		{"scheduled exactly now", Entry{State: EntryScheduled, OccurrenceAt: &now}, EntryUnrecorded},
		{"scheduled future", Entry{State: EntryScheduled, OccurrenceAt: &future}, EntryScheduled},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := c.e.DisplayState(now); got != c.want {
				t.Fatalf("got %q, want %q", got, c.want)
			}
		})
	}
}

func TestEvaluateAttention(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	ago := func(d time.Duration) *time.Time { v := now.Add(-d); return &v }
	gap := func(h int) *int { return &h }
	bp := Tracker{
		TrackerID: "bp", Status: TrackerActive, CreatedAt: now.Add(-30 * 24 * time.Hour),
		Fields: []Field{
			{FieldID: "sys", Type: FieldNumber, Status: FieldActive, Range: &Range{Low: fp(90), High: fp(140)}},
			{FieldID: "dia", Type: FieldNumber, Status: FieldActive, Range: &Range{High: fp(90)}},
			{FieldID: "pulse", Type: FieldNumber, Status: FieldActive},
			{FieldID: "note", Type: FieldText, Status: FieldActive},
		},
	}
	logged := func(id string, at *time.Time, vals map[string]any) Entry {
		return Entry{EntryID: id, State: EntryLogged, OccurredAt: at, Values: vals}
	}
	open := func(id string, at *time.Time) Entry {
		return Entry{EntryID: id, State: EntryScheduled, OccurrenceAt: at}
	}
	withGap := func(t Tracker, h int) Tracker { t.GapHours = gap(h); return t }
	paused := bp
	paused.Status = TrackerPaused
	diaPaused := bp
	diaPaused.Fields = append([]Field(nil), bp.Fields...)
	diaPaused.Fields[1].Status = FieldPaused

	type want struct {
		kind  AttentionKind
		entry string
		field string
	}
	cases := []struct {
		name   string
		t      Tracker
		logged []Entry
		open   []Entry
		want   []want
	}{
		{"nothing wrong", bp, []Entry{logged("e1", ago(time.Hour), map[string]any{"sys": 120.0, "dia": 80.0})}, nil, nil},
		{"never logged, no gap", bp, nil, nil, nil},
		{"high systolic", bp, []Entry{logged("e1", ago(time.Hour), map[string]any{"sys": 150.0, "dia": 80.0})}, nil,
			[]want{{AttentionOutOfRange, "e1", "sys"}}},
		{"low bound", bp, []Entry{logged("e1", ago(time.Hour), map[string]any{"sys": 80.0})}, nil,
			[]want{{AttentionOutOfRange, "e1", "sys"}}},
		{"bounds inclusive", bp, []Entry{logged("e1", ago(time.Hour), map[string]any{"sys": 140.0, "dia": 90.0})}, nil, nil},
		{"later in-range reading clears it", bp, []Entry{
			logged("e2", ago(time.Hour), map[string]any{"sys": 120.0}),
			logged("e1", ago(2*time.Hour), map[string]any{"sys": 160.0}),
		}, nil, nil},
		{"latest carrying the field counts", bp, []Entry{
			logged("e2", ago(time.Hour), map[string]any{"pulse": 70.0}),
			logged("e1", ago(2*time.Hour), map[string]any{"dia": 95.0}),
		}, nil, []want{{AttentionOutOfRange, "e1", "dia"}}},
		{"both fields out", bp, []Entry{logged("e1", ago(time.Hour), map[string]any{"sys": 150.0, "dia": 95.0})}, nil,
			[]want{{AttentionOutOfRange, "e1", "sys"}, {AttentionOutOfRange, "e1", "dia"}}},
		{"paused field's range raises nothing", diaPaused,
			[]Entry{logged("e1", ago(time.Hour), map[string]any{"sys": 150.0, "dia": 95.0})}, nil,
			[]want{{AttentionOutOfRange, "e1", "sys"}}},
		{"skipped entries ignored for range", bp, []Entry{
			{EntryID: "s1", State: EntrySkipped, Values: map[string]any{"sys": 200.0}},
		}, nil, nil},
		{"unrecorded 1h ago", bp, nil, []Entry{open("o1", ago(time.Hour))}, []want{{AttentionUnrecorded, "o1", ""}}},
		{"unrecorded exactly now", bp, nil, []Entry{open("o1", ago(0))}, []want{{AttentionUnrecorded, "o1", ""}}},
		{"unrecorded 47h ago", bp, nil, []Entry{open("o1", ago(47*time.Hour))}, []want{{AttentionUnrecorded, "o1", ""}}},
		{"unrecorded 48h ago has gone quiet", bp, nil, []Entry{open("o1", ago(48*time.Hour))}, nil},
		{"unrecorded 49h ago has gone quiet", bp, nil, []Entry{open("o1", ago(49*time.Hour))}, nil},
		{"future occurrence is not unrecorded", bp, nil, []Entry{open("o1", ago(-time.Hour))}, nil},
		{"unrecorded oldest first", bp, nil, []Entry{open("o2", ago(time.Hour)), open("o1", ago(5*time.Hour))},
			[]want{{AttentionUnrecorded, "o1", ""}, {AttentionUnrecorded, "o2", ""}}},
		{"gap past since last log", withGap(bp, 72), []Entry{logged("e1", ago(73*time.Hour), nil)}, nil,
			[]want{{AttentionGap, "", ""}}},
		{"gap not yet past", withGap(bp, 72), []Entry{logged("e1", ago(71*time.Hour), nil)}, nil, nil},
		{"gap exactly reached is not past", withGap(bp, 72), []Entry{logged("e1", ago(72*time.Hour), nil)}, nil, nil},
		{"gap since created when never logged", withGap(bp, 72), nil, nil, []want{{AttentionGap, "", ""}}},
		{"order: unrecorded, out_of_range, gap", withGap(bp, 1),
			[]Entry{logged("e1", ago(3*time.Hour), map[string]any{"sys": 150.0})},
			[]Entry{open("o1", ago(2*time.Hour))},
			[]want{{AttentionUnrecorded, "o1", ""}, {AttentionOutOfRange, "e1", "sys"}, {AttentionGap, "", ""}}},
		{"paused tracker needs nothing", withGap(paused, 1),
			[]Entry{logged("e1", ago(3*time.Hour), map[string]any{"sys": 150.0})},
			[]Entry{open("o1", ago(2*time.Hour))}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := EvaluateAttention(c.t, now, c.logged, c.open)
			if len(got) != len(c.want) {
				t.Fatalf("got %+v, want %+v", got, c.want)
			}
			for i, w := range c.want {
				if got[i].Kind != w.kind || got[i].EntryID != w.entry || got[i].FieldID != w.field {
					t.Fatalf("[%d] got %+v, want %+v", i, got[i], w)
				}
			}
		})
	}
}

func TestEvaluateAttention_details(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	last := now.Add(-80 * time.Hour)
	h := 72
	tr := Tracker{Status: TrackerActive, GapHours: &h, Fields: []Field{{FieldID: "sys", Type: FieldNumber, Status: FieldActive, Range: &Range{High: fp(140)}}}}
	got := EvaluateAttention(tr, now, []Entry{{EntryID: "e1", State: EntryLogged, OccurredAt: &last, Values: map[string]any{"sys": 150.0}}}, nil)
	if len(got) != 2 {
		t.Fatalf("got %+v", got)
	}
	if got[0].Value != 150 || got[0].Range.High == nil || *got[0].Range.High != 140 {
		t.Fatalf("out_of_range detail: %+v", got[0])
	}
	if !got[1].Since.Equal(last) || got[1].GapHours != 72 {
		t.Fatalf("gap detail: %+v", got[1])
	}
}

func TestLastLoggedAt(t *testing.T) {
	a := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	b := a.Add(time.Hour)
	if LastLoggedAt(nil) != nil {
		t.Fatal("nil for none")
	}
	got := LastLoggedAt([]Entry{{State: EntryLogged, OccurredAt: &a}, {State: EntryLogged, OccurredAt: &b}, {State: EntrySkipped}})
	if got == nil || !got.Equal(b) {
		t.Fatalf("got %v", got)
	}
}
