package domain

import (
	"testing"
	"time"
)

func TestRankAttention(t *testing.T) {
	now := time.Date(2026, 11, 8, 20, 0, 0, 0, time.UTC)
	unrec := func(id string, ago time.Duration) Attention {
		return Attention{Kind: AttentionUnrecorded, EntryID: id, OccurrenceAt: now.Add(-ago)}
	}
	oor := func(id, field string, ago time.Duration) Attention {
		return Attention{Kind: AttentionOutOfRange, EntryID: id, FieldID: field, OccurredAt: now.Add(-ago)}
	}
	gap := func(sinceAgo time.Duration, hours int) Attention {
		return Attention{Kind: AttentionGap, Since: now.Add(-sinceAgo), GapHours: hours}
	}
	type pick struct{ tracker, key string }
	key := func(a TrackerAttention) pick {
		k := string(a.Kind) + ":" + a.EntryID + a.FieldID
		if a.Kind == AttentionGap {
			k = string(a.Kind) + ":" + a.Since.Format(time.RFC3339)
		}
		return pick{a.TrackerID, k}
	}
	cases := []struct {
		name  string
		in    map[string][]Attention
		limit int
		want  []pick
	}{
		{"nothing wrong", map[string][]Attention{"meds": nil, "bp": {}}, 3, nil},
		{
			"one per tracker: the evening unrecorded dose over the morning one",
			map[string][]Attention{"meds": {unrec("morning", 12*time.Hour), unrec("evening", time.Hour)}},
			3,
			[]pick{{"meds", "unrecorded:evening"}},
		},
		{
			"one per tracker: unrecorded outranks out of range and gap on the same tracker",
			map[string][]Attention{"bp": {oor("e1", "sys", time.Minute), gap(50*time.Hour, 24), unrec("o1", 40*time.Hour)}},
			3,
			[]pick{{"bp", "unrecorded:o1"}},
		},
		{
			"one per tracker: the most recent reading out of range",
			map[string][]Attention{"bp": {oor("old", "sys", 5*time.Hour), oor("new", "dia", time.Hour)}},
			3,
			[]pick{{"bp", "out_of_range:newdia"}},
		},
		{
			"two fields out on one reading show the first field",
			map[string][]Attention{"bp": {oor("e1", "sys", time.Hour), oor("e1", "dia", time.Hour)}},
			3,
			[]pick{{"bp", "out_of_range:e1sys"}},
		},
		{
			"across trackers: by kind, then most recent first",
			map[string][]Attention{
				"weight":  {gap(30*time.Hour, 24)},
				"bp":      {oor("r-old", "sys", 10*time.Hour)},
				"sugar":   {oor("r-new", "mg", time.Hour)},
				"meds":    {unrec("dose-old", 30*time.Hour)},
				"inhaler": {unrec("puff-new", 2*time.Hour)},
			},
			0,
			[]pick{
				{"inhaler", "unrecorded:puff-new"}, {"meds", "unrecorded:dose-old"},
				{"sugar", "out_of_range:r-newmg"}, {"bp", "out_of_range:r-oldsys"},
				{"weight", "gap:" + now.Add(-30*time.Hour).Format(time.RFC3339)},
			},
		},
		{
			"gaps: the one crossed most recently first",
			map[string][]Attention{
				"a": {gap(100*time.Hour, 24)}, // crossed 76h ago
				"b": {gap(30*time.Hour, 24)},  // crossed 6h ago
			},
			3,
			[]pick{
				{"b", "gap:" + now.Add(-30*time.Hour).Format(time.RFC3339)},
				{"a", "gap:" + now.Add(-100*time.Hour).Format(time.RFC3339)},
			},
		},
		{
			"capped at limit, after ranking",
			map[string][]Attention{
				"g":  {gap(30*time.Hour, 24)},
				"o":  {oor("r", "f", time.Hour)},
				"u1": {unrec("x", 3*time.Hour)},
				"u2": {unrec("y", 2*time.Hour)},
			},
			3,
			[]pick{{"u2", "unrecorded:y"}, {"u1", "unrecorded:x"}, {"o", "out_of_range:rf"}},
		},
		{
			"ties fall back to tracker id",
			map[string][]Attention{"b": {unrec("x", time.Hour)}, "a": {unrec("y", time.Hour)}},
			3,
			[]pick{{"a", "unrecorded:y"}, {"b", "unrecorded:x"}},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := RankAttention(c.in, c.limit)
			if len(got) != len(c.want) {
				t.Fatalf("got %d items %+v, want %v", len(got), got, c.want)
			}
			for i := range got {
				if k := key(got[i]); k != c.want[i] {
					t.Fatalf("item %d: got %v, want %v (all: %+v)", i, k, c.want[i], got)
				}
			}
		})
	}
}

func TestRankAttention_fromEvaluateAttention(t *testing.T) {
	now := time.Date(2026, 11, 8, 20, 0, 0, 0, time.UTC)
	at := func(ago time.Duration) *time.Time { v := now.Add(-ago); return &v }
	bp := Tracker{
		TrackerID: "bp", Status: TrackerActive, CreatedAt: now.Add(-30 * 24 * time.Hour),
		Fields: []Field{{FieldID: "sys", Type: FieldNumber, Status: FieldActive, Range: &Range{High: fp(140)}}},
	}
	logged := []Entry{{EntryID: "high", State: EntryLogged, OccurredAt: at(time.Hour), Values: map[string]any{"sys": 170.0}}}
	att := EvaluateAttention(bp, now, logged, nil)
	if len(att) != 1 || !att[0].OccurredAt.Equal(*at(time.Hour)) {
		t.Fatalf("out_of_range should carry the reading's time: %+v", att)
	}
	got := RankAttention(map[string][]Attention{"bp": att}, 3)
	if len(got) != 1 || got[0].TrackerID != "bp" || got[0].EntryID != "high" {
		t.Fatalf("got %+v", got)
	}
}
