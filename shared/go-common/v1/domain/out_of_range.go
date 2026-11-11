package domain

// OutOfRange is one value of a logged entry that falls outside its field's
// range.
type OutOfRange struct {
	FieldID string
	Value   float64
	Range   Range
}

// OutOfRangeValues is what Entry detail marks: each value of a logged entry
// that falls outside its field's range as the tracker now stands, in field
// order. Only active number fields with a range are checked, as needs
// attention checks them; an entry in any other state has no reading to judge.
func OutOfRangeValues(t Tracker, e Entry) []OutOfRange {
	if e.State != EntryLogged {
		return nil
	}
	var out []OutOfRange
	for _, f := range t.Fields {
		if f.Type != FieldNumber || f.Range == nil || f.Status != FieldActive {
			continue
		}
		v, ok := numberValue(e.Values[f.FieldID])
		if ok && !f.Range.Contains(v) {
			out = append(out, OutOfRange{FieldID: f.FieldID, Value: v, Range: *f.Range})
		}
	}
	return out
}
