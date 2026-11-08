package domain

import (
	_ "embed"
	"encoding/json"
	"sync"
)

//go:embed templates.json
var templatesJSON []byte

// Template is one entry of the tracker template catalogue (the PRD's Tracker
// template), shaped as the CatalogTemplate schema. Its fields carry no ids:
// creating a tracker from it assigns them.
type Template struct {
	TemplateID string          `json:"template_id"`
	Name       string          `json:"name"`
	Icon       string          `json:"icon"`
	Color      string          `json:"color"`
	Fields     []TemplateField `json:"fields"`
	GapHours   *int            `json:"gap_hours,omitempty"`
}

// TemplateField is a field as Add tracker would send it (TrackerFieldWrite).
type TemplateField struct {
	Label    string           `json:"label"`
	Type     FieldType        `json:"type"`
	Unit     string           `json:"unit,omitempty"`
	Required bool             `json:"required"`
	Range    *TemplateRange   `json:"range,omitempty"`
	Multiple bool             `json:"multiple,omitempty"`
	Options  []TemplateOption `json:"options,omitempty"`
}

type TemplateRange struct {
	Low  *float64 `json:"low,omitempty"`
	High *float64 `json:"high,omitempty"`
}

type TemplateOption struct {
	Label string `json:"label"`
}

var (
	templatesOnce  sync.Once
	templatesCache []Template
)

// Templates returns the embedded catalogue in the order Add tracker shows it,
// parsed once. It panics on a malformed catalogue — a build-time defect caught
// by TestTemplates.
func Templates() []Template {
	templatesOnce.Do(func() {
		if err := json.Unmarshal(templatesJSON, &templatesCache); err != nil {
			panic("domain: malformed v1 templates.json: " + err.Error())
		}
	})
	return templatesCache
}
