package domain

import (
	_ "embed"
	"encoding/json"
	"sync"
)

//go:embed templates.json
var templatesJSON []byte

// TrackerTemplate is a system-seeded, read-only starting point for a tracker. It
// is the creatable shape of a tracker minus per-receiver identity. Clients clone
// one by POSTing it (optionally edited) to create a Tracker — there is no
// server-side clone link.
type TrackerTemplate struct {
	TemplateID string      `json:"template_id"`
	Name       string      `json:"name"`
	Kind       TrackerKind `json:"kind"`
	Icon       string      `json:"icon,omitempty"`
	Color      string      `json:"color,omitempty"`
	Fields     []Field     `json:"fields"`
}

var (
	templatesOnce  sync.Once
	templatesCache []TrackerTemplate
)

// Templates returns the embedded catalog, parsed once. It panics on a malformed
// catalog — that is a build-time defect caught by TestTemplates_loadsAndIsValid.
func Templates() []TrackerTemplate {
	templatesOnce.Do(func() {
		if err := json.Unmarshal(templatesJSON, &templatesCache); err != nil {
			panic("domain: malformed templates.json: " + err.Error())
		}
	})
	return templatesCache
}
