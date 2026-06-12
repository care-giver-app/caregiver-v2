package domain

import (
	"fmt"
	"time"
)

// Breach reports a number value outside its field threshold. Computed on read,
// never stored.
type Breach struct {
	Key   string  `json:"key"`
	Value float64 `json:"value"`
	Bound string  `json:"bound"` // "min" | "max"
	Limit float64 `json:"limit"`
}

// ValidateValues checks a values map against a tracker's field schema. It returns
// a descriptive, field-named error on the first problem, or nil when valid.
// Numbers are float64 because JSON decodes numeric values to float64.
func ValidateValues(fields []Field, values map[string]any) error {
	byKey := make(map[string]Field, len(fields))
	for _, f := range fields {
		byKey[f.Key] = f
	}
	for key := range values {
		if _, ok := byKey[key]; !ok {
			return fmt.Errorf("unknown field %q", key)
		}
	}
	for _, f := range fields {
		v, present := values[f.Key]
		if !present {
			if f.Required {
				return fmt.Errorf("field %q is required", f.Key)
			}
			continue
		}
		if err := validateValue(f, v); err != nil {
			return err
		}
	}
	return nil
}

func validateValue(f Field, v any) error {
	switch f.Type {
	case FieldNumber:
		if _, ok := v.(float64); !ok {
			return fmt.Errorf("field %q must be a number", f.Key)
		}
	case FieldText:
		if _, ok := v.(string); !ok {
			return fmt.Errorf("field %q must be a string", f.Key)
		}
	case FieldBoolean:
		if _, ok := v.(bool); !ok {
			return fmt.Errorf("field %q must be a boolean", f.Key)
		}
	case FieldEnum:
		s, ok := v.(string)
		if !ok {
			return fmt.Errorf("field %q must be a string", f.Key)
		}
		for _, opt := range f.Options {
			if s == opt {
				return nil
			}
		}
		return fmt.Errorf("field %q must be one of the allowed options", f.Key)
	case FieldDatetime:
		s, ok := v.(string)
		if !ok {
			return fmt.Errorf("field %q must be an RFC3339 datetime string", f.Key)
		}
		if _, err := time.Parse(time.RFC3339, s); err != nil {
			return fmt.Errorf("field %q must be an RFC3339 datetime string", f.Key)
		}
	default:
		return fmt.Errorf("field %q has an unknown type", f.Key)
	}
	return nil
}

// Breaches returns the threshold breaches for the given values. Only number
// fields with a threshold are considered; out-of-range values are valid data and
// are flagged, never rejected.
func Breaches(fields []Field, values map[string]any) []Breach {
	var out []Breach
	for _, f := range fields {
		if f.Type != FieldNumber || f.Threshold == nil {
			continue
		}
		v, ok := values[f.Key].(float64)
		if !ok {
			continue
		}
		if f.Threshold.Min != nil && v < *f.Threshold.Min {
			out = append(out, Breach{Key: f.Key, Value: v, Bound: "min", Limit: *f.Threshold.Min})
		}
		if f.Threshold.Max != nil && v > *f.Threshold.Max {
			out = append(out, Breach{Key: f.Key, Value: v, Bound: "max", Limit: *f.Threshold.Max})
		}
	}
	return out
}
