package domain

import (
	"sort"
	"time"
)

// UnrecordedWindow is how long after its time an unrecorded occurrence keeps
// needing attention.
const UnrecordedWindow = 48 * time.Hour

type AttentionKind string

const (
	AttentionUnrecorded AttentionKind = "unrecorded"
	AttentionOutOfRange AttentionKind = "out_of_range"
	AttentionGap        AttentionKind = "gap"
)

// Attention is one thing wrong with a tracker right now. Which fields are set
// depends on Kind: unrecorded sets EntryID and OccurrenceAt; out_of_range sets
// EntryID, FieldID, Value and Range; gap sets Since and GapHours.
type Attention struct {
	Kind         AttentionKind
	EntryID      string
	OccurrenceAt time.Time
	FieldID      string
	Value        float64
	Range        Range
	Since        time.Time
	GapHours     int
}

// EvaluateAttention works out what is wrong with t at now, from its recent
// logged entries (newest first) and its open scheduled entries. A paused tracker
// never needs attention. The result is ordered unrecorded, then out_of_range
// (in field order), then gap; unrecorded occurrences are oldest first.
//
// Every number field with a range is checked, paused fields included: its
// latest reading stands until a later one comes back in range.
func EvaluateAttention(t Tracker, now time.Time, logged, open []Entry) []Attention {
	if t.Status == TrackerPaused {
		return nil
	}
	var out []Attention

	var unrecorded []Attention
	for _, e := range open {
		if e.State != EntryScheduled || e.OccurrenceAt == nil {
			continue
		}
		at := *e.OccurrenceAt
		if !at.After(now) && at.After(now.Add(-UnrecordedWindow)) {
			unrecorded = append(unrecorded, Attention{Kind: AttentionUnrecorded, EntryID: e.EntryID, OccurrenceAt: at})
		}
	}
	sort.SliceStable(unrecorded, func(i, j int) bool { return unrecorded[i].OccurrenceAt.Before(unrecorded[j].OccurrenceAt) })
	out = append(out, unrecorded...)

	for _, f := range t.Fields {
		if f.Type != FieldNumber || f.Range == nil {
			continue
		}
		for _, e := range logged {
			v, ok := numberValue(e.Values[f.FieldID])
			if e.State != EntryLogged || !ok {
				continue
			}
			if !f.Range.Contains(v) {
				out = append(out, Attention{Kind: AttentionOutOfRange, EntryID: e.EntryID, FieldID: f.FieldID, Value: v, Range: *f.Range})
			}
			break
		}
	}

	if t.GapHours != nil {
		since := t.CreatedAt
		if last := LastLoggedAt(logged); last != nil {
			since = *last
		}
		if now.Sub(since) > time.Duration(*t.GapHours)*time.Hour {
			out = append(out, Attention{Kind: AttentionGap, Since: since, GapHours: *t.GapHours})
		}
	}
	return out
}

// LastLoggedAt is the latest occurred_at among logged entries, or nil when
// there are none.
func LastLoggedAt(logged []Entry) *time.Time {
	var last *time.Time
	for _, e := range logged {
		if e.State == EntryLogged && e.OccurredAt != nil && (last == nil || e.OccurredAt.After(*last)) {
			last = e.OccurredAt
		}
	}
	return last
}

// numberValue reads a stored number. Values unmarshal from DynamoDB and JSON as
// float64; the integer cases cover values built in code.
func numberValue(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case float32:
		return float64(n), true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	}
	return 0, false
}
