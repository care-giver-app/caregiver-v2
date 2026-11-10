package domain

import (
	"sort"
	"time"
)

// TrackerAttention is one needs-attention item on a receiver's Home, with the
// tracker it is about.
type TrackerAttention struct {
	TrackerID string
	Attention
}

// kindRank orders the kinds by how much they matter: unrecorded care, then a
// reading out of range, then a gap.
func kindRank(k AttentionKind) int {
	switch k {
	case AttentionUnrecorded:
		return 0
	case AttentionOutOfRange:
		return 1
	case AttentionGap:
		return 2
	}
	return 3
}

// when is the moment an item is "recent" by: an unrecorded occurrence's
// scheduled time, an out-of-range reading's time, and for a gap the moment
// the tracker went past it.
func (a Attention) when() time.Time {
	switch a.Kind {
	case AttentionUnrecorded:
		return a.OccurrenceAt
	case AttentionOutOfRange:
		return a.OccurredAt
	case AttentionGap:
		return a.Since.Add(time.Duration(a.GapHours) * time.Hour)
	}
	return time.Time{}
}

// moreImportant reports whether a outranks b: by kind, then most recent first.
func moreImportant(a, b Attention) bool {
	if ra, rb := kindRank(a.Kind), kindRank(b.Kind); ra != rb {
		return ra < rb
	}
	return a.when().After(b.when())
}

// RankAttention turns each active tracker's EvaluateAttention result, keyed by
// tracker_id, into a receiver's needs attention: at most one item per tracker —
// the one that matters most by kind, then the most recent of that kind — then
// ordered across trackers by kind and most recent first, capped at limit (no
// cap when limit <= 0). Ties fall back to tracker_id, so the order is stable.
// Within one tracker an equal pair keeps EvaluateAttention's order, so two
// fields out of range on one reading show the first field.
func RankAttention(byTracker map[string][]Attention, limit int) []TrackerAttention {
	var out []TrackerAttention
	for trackerID, items := range byTracker {
		if len(items) == 0 {
			continue
		}
		best := items[0]
		for _, a := range items[1:] {
			if moreImportant(a, best) {
				best = a
			}
		}
		out = append(out, TrackerAttention{TrackerID: trackerID, Attention: best})
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if moreImportant(a.Attention, b.Attention) {
			return true
		}
		if moreImportant(b.Attention, a.Attention) {
			return false
		}
		return a.TrackerID < b.TrackerID
	})
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out
}
