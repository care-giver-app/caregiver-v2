package domain

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// ErrInvalidTracker is wrapped by every tracker validation error below, so a
// handler can map them all to 400 with errors.Is and show err.Error().
var ErrInvalidTracker = errors.New("invalid tracker")

func invalid(msg string) error { return fmt.Errorf("%w: %s", ErrInvalidTracker, msg) }

var (
	ErrInvalidTrackerName = invalid("name must be 1-100 characters")
	ErrInvalidColor       = invalid("color must be #RRGGBB")
	ErrInvalidGapHours    = invalid("gap_hours must be at least 1")
	// ErrInvalidField is a field or option that breaks a shape rule (label,
	// type, unit, range, multiple, options, status).
	ErrInvalidField = invalid("invalid field")
	// ErrFieldOmitted: an edit left out an existing field. Fields are paused, never removed.
	ErrFieldOmitted = invalid("an existing field was left out")
	// ErrOptionOmitted: an edit left out an existing option. Options are retired, never removed.
	ErrOptionOmitted = invalid("an existing choice option was left out")
	// ErrFieldTypeChanged: an edit changed an existing field's type, which is fixed.
	ErrFieldTypeChanged = invalid("an existing field's type cannot change")
	// ErrUnknownField: an edit named a field_id the tracker does not have, or named one twice.
	ErrUnknownField = invalid("unknown field_id")
	// ErrUnknownOption: an edit named an option_id the field does not have, or named one twice.
	ErrUnknownOption = invalid("unknown option_id")
)

const (
	MaxTrackerNameLength = 100
	MaxFieldLabelLength  = 100
	MaxFieldUnitLength   = 20
)

var colorPattern = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

// ValidateTrackerName trims surrounding whitespace and requires 1–100
// characters. It returns the trimmed name.
func ValidateTrackerName(s string) (string, error) {
	name := strings.TrimSpace(s)
	if n := utf8.RuneCountInString(name); n < 1 || n > MaxTrackerNameLength {
		return "", ErrInvalidTrackerName
	}
	return name, nil
}

func ValidateColor(s string) error {
	if !colorPattern.MatchString(s) {
		return ErrInvalidColor
	}
	return nil
}

// ValidateGapHours accepts nil (no gap) or a value of at least 1.
func ValidateGapHours(h *int) error {
	if h != nil && *h < 1 {
		return ErrInvalidGapHours
	}
	return nil
}

// FieldWrite is a field as Add tracker or Edit tracker sends it. FieldID is
// empty for a new field; an empty Status means active.
type FieldWrite struct {
	FieldID  string
	Label    string
	Type     FieldType
	Unit     string
	Required bool
	Status   FieldStatus
	Range    *Range
	Multiple bool
	Options  []OptionWrite
}

// OptionWrite is a choice option as sent. OptionID is empty for a new option;
// an empty Status means active.
type OptionWrite struct {
	OptionID string
	Label    string
	Status   OptionStatus
}

// NewFields validates a new tracker's fields and assigns every field and
// option a fresh id. Any id the caller sent is refused: a new tracker has none.
func NewFields(ws []FieldWrite, now time.Time) ([]Field, error) {
	return ApplyFieldChanges(nil, ws, now)
}

// ApplyFieldChanges applies Edit tracker's fields to the existing ones, in the
// order sent. Every existing field must be named by field_id with its type
// unchanged, and every existing option of a choice field must be named by
// option_id; anything without an id is new and gets a fresh one. Pausing a
// field stamps PausedAt with now (kept if it was already paused); resuming
// clears it.
func ApplyFieldChanges(existing []Field, ws []FieldWrite, now time.Time) ([]Field, error) {
	byID := make(map[string]Field, len(existing))
	for _, f := range existing {
		byID[f.FieldID] = f
	}
	seen := make(map[string]bool, len(ws))
	out := make([]Field, 0, len(ws))
	for _, w := range ws {
		var old *Field
		if w.FieldID != "" {
			f, ok := byID[w.FieldID]
			if !ok || seen[w.FieldID] {
				return nil, fieldErr(ErrUnknownField, w.FieldID)
			}
			seen[w.FieldID] = true
			if w.Type != f.Type {
				return nil, fieldErr(ErrFieldTypeChanged, f.Label)
			}
			old = &f
		}
		f, err := buildField(old, w, now)
		if err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	for _, f := range existing {
		if !seen[f.FieldID] {
			return nil, fieldErr(ErrFieldOmitted, f.Label)
		}
	}
	return out, nil
}

func fieldErr(sentinel error, name string) error { return fmt.Errorf("%w (%q)", sentinel, name) }

func shapeErr(label, msg string) error {
	return fmt.Errorf("%w: field %q: %s", ErrInvalidField, label, msg)
}

// buildField validates w's shape and builds the stored field, keeping old's id
// (and option ids and paused time) when it edits an existing field.
func buildField(old *Field, w FieldWrite, now time.Time) (Field, error) {
	label := strings.TrimSpace(w.Label)
	if n := utf8.RuneCountInString(label); n < 1 || n > MaxFieldLabelLength {
		return Field{}, shapeErr(w.Label, "label must be 1-100 characters")
	}
	if !w.Type.Valid() {
		return Field{}, shapeErr(label, "type must be number, text, boolean, choice or datetime")
	}
	status := w.Status
	if status == "" {
		status = FieldActive
	}
	if !status.Valid() {
		return Field{}, shapeErr(label, "status must be active or paused")
	}
	unit := strings.TrimSpace(w.Unit)
	if w.Type != FieldNumber && (unit != "" || w.Range != nil) {
		return Field{}, shapeErr(label, "unit and range are for number fields only")
	}
	if utf8.RuneCountInString(unit) > MaxFieldUnitLength {
		return Field{}, shapeErr(label, "unit must be at most 20 characters")
	}
	if r := w.Range; r != nil && r.Low != nil && r.High != nil && *r.Low > *r.High {
		return Field{}, shapeErr(label, "range low must not be above high")
	}
	if w.Type != FieldChoice && (w.Multiple || len(w.Options) > 0) {
		return Field{}, shapeErr(label, "multiple and options are for choice fields only")
	}

	f := Field{Label: label, Type: w.Type, Unit: unit, Required: w.Required, Status: status, Multiple: w.Multiple}
	if w.Range != nil && (w.Range.Low != nil || w.Range.High != nil) {
		r := *w.Range
		f.Range = &r
	}
	if old != nil {
		f.FieldID = old.FieldID
	} else {
		f.FieldID = uuid.NewString()
	}
	if status == FieldPaused {
		if old != nil && old.Status == FieldPaused && old.PausedAt != nil {
			f.PausedAt = old.PausedAt
		} else {
			at := now
			f.PausedAt = &at
		}
	}
	if w.Type == FieldChoice {
		var oldOptions []ChoiceOption
		if old != nil {
			oldOptions = old.Options
		}
		opts, err := applyOptions(label, oldOptions, w.Options)
		if err != nil {
			return Field{}, err
		}
		f.Options = opts
	}
	return f, nil
}

func applyOptions(field string, existing []ChoiceOption, ws []OptionWrite) ([]ChoiceOption, error) {
	known := make(map[string]bool, len(existing))
	for _, o := range existing {
		known[o.OptionID] = true
	}
	seen := make(map[string]bool, len(ws))
	out := make([]ChoiceOption, 0, len(ws))
	for _, w := range ws {
		label := strings.TrimSpace(w.Label)
		if n := utf8.RuneCountInString(label); n < 1 || n > MaxFieldLabelLength {
			return nil, shapeErr(field, "every option needs a label of 1-100 characters")
		}
		status := w.Status
		if status == "" {
			status = OptionActive
		}
		if !status.Valid() {
			return nil, shapeErr(field, "option status must be active or retired")
		}
		id := w.OptionID
		if id == "" {
			id = uuid.NewString()
		} else if !known[id] || seen[id] {
			return nil, fieldErr(ErrUnknownOption, w.OptionID)
		}
		seen[id] = true
		out = append(out, ChoiceOption{OptionID: id, Label: label, Status: status})
	}
	for _, o := range existing {
		if !seen[o.OptionID] {
			return nil, fieldErr(ErrOptionOmitted, o.Label)
		}
	}
	return out, nil
}
