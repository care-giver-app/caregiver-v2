# B3a — Core Care Domain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Receivers + Trackers + Events API surface (and the seeded tracker-template catalog) so the C1 iOS MVP can add a receiver, define trackers, log events, and view paginated history — all structurally isolated per care group.

**Architecture:** Three new multi-table DynamoDB entities (`receiver`, `tracker`, `event`) behind per-entity Go stores, OpenAPI-first HTTP handlers that reuse B1's `auth`/`httpx` authorization seam unchanged, custom field-schema validation in `domain`, an embedded template catalog, and CDK wiring for the new tables. `care_group_id` is denormalized onto `tracker` and `event` rows so authorization is a single GetItem.

**Tech Stack:** Go 1.23.7 (`shared/go-common`, `api`), AWS SDK v2 DynamoDB, testcontainers + `amazon/dynamodb-local:2.5.2`, OpenAPI 3 + oapi-codegen, AWS CDK (TypeScript).

**Source spec:** `docs/specs/2026-06-12-b3a-core-care-domain-design.md`

**Conventions (from `CLAUDE.md`):**

- Go is pinned at **1.23.7**; never `go get …@latest`.
- Conventional Commits, **lowercase** subject (`feat: add x`).
- After editing `shared/openapi/openapi.yaml`, run `cd shared/types-go && make codegen` and commit regenerated files (CI has a codegen-drift check).
- Tests that touch stores/handlers need Docker running.
- Branch is `b3a-core-care-domain` (already created off `main`). Do **not** merge; open a PR at the end.

**Pattern note (decided for this slice):** B1 domain types carry only `dynamodbav` tags and handlers shape JSON with `map[string]any`. B3a entities are larger and nested (fields, values), so B3a domain types carry **both `dynamodbav` and `json` tags** and handlers JSON-encode domain values directly (events wrap the domain value to add a computed `breaches` array). This is a deliberate, local extension of the B1 pattern to avoid hand-mapping large nested structs.

---

## Section A — Domain models, validation & template catalog

**Files in this section:**

- Create: `shared/go-common/domain/care.go` — Receiver, Tracker, Field, Threshold, Event types + enums + `Valid()` helpers
- Create: `shared/go-common/domain/care_test.go`
- Create: `shared/go-common/domain/validate.go` — `ValidateValues`, `Breaches`
- Create: `shared/go-common/domain/validate_test.go`
- Create: `shared/go-common/domain/templates.go` — embedded catalog loader
- Create: `shared/go-common/domain/templates.json` — the seeded catalog
- Create: `shared/go-common/domain/templates_test.go`

**Section gate (acceptance criteria):**

- New domain types compile with `dynamodbav` + `json` tags; `TrackerKind` and `FieldType` have `Valid()` guards.
- `ValidateValues` rejects unknown keys, missing required fields, and type mismatches (number/text/boolean/enum/datetime) with a field-named error; accepts valid payloads.
- `Breaches` returns per-field min/max breaches for numbers and ignores fields without thresholds.
- `Templates()` parses the embedded `templates.json` into `[]TrackerTemplate`; a CI test fails the build if the catalog is malformed or has an invalid kind/field type.
- `cd shared/go-common && go test ./domain/...` passes.

---

### Task A1: Core care domain types

**Files:**

- Create: `shared/go-common/domain/care.go`
- Test: `shared/go-common/domain/care_test.go`

- [ ] **Step 1: Write the failing test**

```go
// shared/go-common/domain/care_test.go
package domain

import "testing"

func TestTrackerKind_Valid(t *testing.T) {
	for _, k := range []TrackerKind{KindEvent, KindMeasurement, KindScheduled} {
		if !k.Valid() {
			t.Fatalf("%q should be valid", k)
		}
	}
	if TrackerKind("custom").Valid() {
		t.Fatal("custom should be invalid")
	}
	if TrackerKind("event_with_note").Valid() {
		t.Fatal("event_with_note was dropped and must be invalid")
	}
}

func TestFieldType_Valid(t *testing.T) {
	for _, ft := range []FieldType{FieldNumber, FieldText, FieldBoolean, FieldEnum, FieldDatetime} {
		if !ft.Valid() {
			t.Fatalf("%q should be valid", ft)
		}
	}
	if FieldType("currency").Valid() {
		t.Fatal("currency should be invalid")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shared/go-common && go test ./domain/ -run 'TestTrackerKind_Valid|TestFieldType_Valid' -v`
Expected: FAIL — undefined `TrackerKind`, `FieldType`, etc.

- [ ] **Step 3: Write minimal implementation**

```go
// shared/go-common/domain/care.go
package domain

import "time"

// TrackerKind is a semantic/presentation hint. event_with_note was dropped (see
// spec §6.3): the built-in note covers comments and a required text field covers
// "the note is the point".
type TrackerKind string

const (
	KindEvent       TrackerKind = "event"
	KindMeasurement TrackerKind = "measurement"
	KindScheduled   TrackerKind = "scheduled" // reserved; Schedule entity is B3b
)

func (k TrackerKind) Valid() bool {
	return k == KindEvent || k == KindMeasurement || k == KindScheduled
}

// FieldType is the data type of a tracker field.
type FieldType string

const (
	FieldNumber   FieldType = "number"
	FieldText     FieldType = "text"
	FieldBoolean  FieldType = "boolean"
	FieldEnum     FieldType = "enum"
	FieldDatetime FieldType = "datetime"
)

func (t FieldType) Valid() bool {
	switch t {
	case FieldNumber, FieldText, FieldBoolean, FieldEnum, FieldDatetime:
		return true
	}
	return false
}

// Threshold is an optional min/max bound on a number field. Pointers distinguish
// "unset" from a real zero bound.
type Threshold struct {
	Min *float64 `dynamodbav:"min,omitempty" json:"min,omitempty"`
	Max *float64 `dynamodbav:"max,omitempty" json:"max,omitempty"`
}

// Field is one typed slot in a tracker's schema. Key is the stable identifier
// used as the key in Event.Values; Label is the display name.
type Field struct {
	Key       string     `dynamodbav:"key" json:"key"`
	Label     string     `dynamodbav:"label" json:"label"`
	Type      FieldType  `dynamodbav:"type" json:"type"`
	Unit      string     `dynamodbav:"unit,omitempty" json:"unit,omitempty"`
	Required  bool       `dynamodbav:"required" json:"required"`
	Options   []string   `dynamodbav:"options,omitempty" json:"options,omitempty"` // required iff type==enum
	Threshold *Threshold `dynamodbav:"threshold,omitempty" json:"threshold,omitempty"` // number only
}

// Receiver is a care recipient in a group.
type Receiver struct {
	ReceiverID  string    `dynamodbav:"receiver_id" json:"receiver_id"`
	CareGroupID string    `dynamodbav:"care_group_id" json:"care_group_id"`
	Name        string    `dynamodbav:"name" json:"name"`
	DateOfBirth string    `dynamodbav:"date_of_birth,omitempty" json:"date_of_birth,omitempty"` // YYYY-MM-DD
	CreatedBy   string    `dynamodbav:"created_by" json:"created_by"`
	CreatedAt   time.Time `dynamodbav:"created_at" json:"created_at"`
	Archived    bool      `dynamodbav:"archived" json:"archived"`
}

// Tracker is a per-receiver thing-to-log. care_group_id is denormalized from the
// receiver so authz on tracker/event ops is a single read.
type Tracker struct {
	TrackerID   string      `dynamodbav:"tracker_id" json:"tracker_id"`
	ReceiverID  string      `dynamodbav:"receiver_id" json:"receiver_id"`
	CareGroupID string      `dynamodbav:"care_group_id" json:"care_group_id"`
	Name        string      `dynamodbav:"name" json:"name"`
	Kind        TrackerKind `dynamodbav:"kind" json:"kind"`
	Icon        string      `dynamodbav:"icon,omitempty" json:"icon,omitempty"`
	Color       string      `dynamodbav:"color,omitempty" json:"color,omitempty"`
	Fields      []Field     `dynamodbav:"fields" json:"fields"`
	CreatedBy   string      `dynamodbav:"created_by" json:"created_by"`
	CreatedAt   time.Time   `dynamodbav:"created_at" json:"created_at"`
	Archived    bool        `dynamodbav:"archived" json:"archived"`
}

// Event is a logged entry against a tracker. care_group_id and receiver_id are
// denormalized from the tracker.
type Event struct {
	TrackerID   string         `dynamodbav:"tracker_id" json:"tracker_id"`
	EventID     string         `dynamodbav:"event_id" json:"event_id"`
	CareGroupID string         `dynamodbav:"care_group_id" json:"care_group_id"`
	ReceiverID  string         `dynamodbav:"receiver_id" json:"receiver_id"`
	Values      map[string]any `dynamodbav:"values" json:"values"`
	Note        string         `dynamodbav:"note,omitempty" json:"note,omitempty"`
	OccurredAt  time.Time      `dynamodbav:"occurred_at" json:"occurred_at"`
	LoggedBy    string         `dynamodbav:"logged_by" json:"logged_by"`
	CreatedAt   time.Time      `dynamodbav:"created_at" json:"created_at"`
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shared/go-common && go test ./domain/ -run 'TestTrackerKind_Valid|TestFieldType_Valid' -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shared/go-common/domain/care.go shared/go-common/domain/care_test.go
git commit -m "feat: b3a core care domain types"
```

---

### Task A2: Event value validation & breach evaluation

**Files:**

- Create: `shared/go-common/domain/validate.go`
- Test: `shared/go-common/domain/validate_test.go`

- [ ] **Step 1: Write the failing test**

```go
// shared/go-common/domain/validate_test.go
package domain

import "testing"

func bpFields() []Field {
	max140 := 140.0
	return []Field{
		{Key: "systolic", Label: "Systolic", Type: FieldNumber, Required: true, Threshold: &Threshold{Max: &max140}},
		{Key: "mood", Label: "Mood", Type: FieldEnum, Options: []string{"good", "bad"}},
		{Key: "note_required", Label: "Note", Type: FieldText, Required: false},
	}
}

func TestValidateValues_ok(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": 128.0, "mood": "good"})
	if err != nil {
		t.Fatalf("valid payload rejected: %v", err)
	}
}

func TestValidateValues_unknownKey(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": 128.0, "spo2": 97.0})
	if err == nil {
		t.Fatal("expected error for unknown key")
	}
}

func TestValidateValues_missingRequired(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"mood": "good"})
	if err == nil {
		t.Fatal("expected error for missing required systolic")
	}
}

func TestValidateValues_wrongType(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": "high"})
	if err == nil {
		t.Fatal("expected error for non-number systolic")
	}
}

func TestValidateValues_enumNotInOptions(t *testing.T) {
	err := ValidateValues(bpFields(), map[string]any{"systolic": 120.0, "mood": "meh"})
	if err == nil {
		t.Fatal("expected error for enum value not in options")
	}
}

func TestValidateValues_datetimeParsed(t *testing.T) {
	fields := []Field{{Key: "at", Label: "At", Type: FieldDatetime}}
	if err := ValidateValues(fields, map[string]any{"at": "2026-06-12T14:30:00Z"}); err != nil {
		t.Fatalf("valid RFC3339 rejected: %v", err)
	}
	if err := ValidateValues(fields, map[string]any{"at": "not-a-time"}); err == nil {
		t.Fatal("expected error for unparseable datetime")
	}
}

func TestBreaches(t *testing.T) {
	min120, max140 := 120.0, 140.0
	fields := []Field{
		{Key: "systolic", Type: FieldNumber, Threshold: &Threshold{Max: &max140}},
		{Key: "weight", Type: FieldNumber, Threshold: &Threshold{Min: &min120}},
		{Key: "pulse", Type: FieldNumber}, // no threshold -> never breaches
	}
	got := Breaches(fields, map[string]any{"systolic": 162.0, "weight": 110.0, "pulse": 999.0})
	if len(got) != 2 {
		t.Fatalf("expected 2 breaches, got %d: %+v", len(got), got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shared/go-common && go test ./domain/ -run 'TestValidateValues|TestBreaches' -v`
Expected: FAIL — undefined `ValidateValues`, `Breaches`.

- [ ] **Step 3: Write minimal implementation**

```go
// shared/go-common/domain/validate.go
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shared/go-common && go test ./domain/ -run 'TestValidateValues|TestBreaches' -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shared/go-common/domain/validate.go shared/go-common/domain/validate_test.go
git commit -m "feat: event value validation and breach evaluation"
```

---

### Task A3: Embedded template catalog

**Files:**

- Create: `shared/go-common/domain/templates.json`
- Create: `shared/go-common/domain/templates.go`
- Test: `shared/go-common/domain/templates_test.go`

- [ ] **Step 1: Create the seeded catalog**

```json
// shared/go-common/domain/templates.json
[
  {
    "template_id": "weight",
    "name": "Weight",
    "kind": "measurement",
    "icon": "scalemass",
    "color": "#4F8EF7",
    "fields": [
      {
        "key": "weight",
        "label": "Weight",
        "type": "number",
        "unit": "lb",
        "required": true,
        "threshold": { "min": 80, "max": 400 }
      }
    ]
  },
  {
    "template_id": "blood_pressure",
    "name": "Blood Pressure",
    "kind": "measurement",
    "icon": "heart",
    "color": "#E5484D",
    "fields": [
      {
        "key": "systolic",
        "label": "Systolic",
        "type": "number",
        "unit": "mmHg",
        "required": true,
        "threshold": { "max": 140 }
      },
      {
        "key": "diastolic",
        "label": "Diastolic",
        "type": "number",
        "unit": "mmHg",
        "required": true,
        "threshold": { "max": 90 }
      },
      { "key": "pulse", "label": "Pulse", "type": "number", "unit": "bpm", "required": false }
    ]
  },
  {
    "template_id": "temperature",
    "name": "Temperature",
    "kind": "measurement",
    "icon": "thermometer",
    "color": "#F76808",
    "fields": [
      {
        "key": "temperature",
        "label": "Temperature",
        "type": "number",
        "unit": "°F",
        "required": true,
        "threshold": { "max": 100.4 }
      }
    ]
  },
  {
    "template_id": "medication",
    "name": "Medication",
    "kind": "event",
    "icon": "pills",
    "color": "#30A46C",
    "fields": [
      { "key": "name", "label": "Medication", "type": "text", "required": true },
      { "key": "dose", "label": "Dose", "type": "text", "required": false }
    ]
  },
  {
    "template_id": "meal",
    "name": "Meal",
    "kind": "event",
    "icon": "fork.knife",
    "color": "#FFB224",
    "fields": [
      {
        "key": "meal",
        "label": "Meal",
        "type": "enum",
        "required": true,
        "options": ["breakfast", "lunch", "dinner", "snack"]
      },
      { "key": "ate_well", "label": "Ate well", "type": "boolean", "required": false }
    ]
  },
  {
    "template_id": "mood",
    "name": "Mood",
    "kind": "event",
    "icon": "face.smiling",
    "color": "#8E4EC6",
    "fields": [
      {
        "key": "mood",
        "label": "Mood",
        "type": "enum",
        "required": true,
        "options": ["great", "ok", "low", "bad"]
      }
    ]
  }
]
```

- [ ] **Step 2: Write the failing test**

```go
// shared/go-common/domain/templates_test.go
package domain

import "testing"

func TestTemplates_loadsAndIsValid(t *testing.T) {
	tps := Templates()
	if len(tps) == 0 {
		t.Fatal("expected a non-empty template catalog")
	}
	seen := map[string]bool{}
	for _, tp := range tps {
		if tp.TemplateID == "" || tp.Name == "" {
			t.Fatalf("template missing id/name: %+v", tp)
		}
		if seen[tp.TemplateID] {
			t.Fatalf("duplicate template_id %q", tp.TemplateID)
		}
		seen[tp.TemplateID] = true
		if !tp.Kind.Valid() {
			t.Fatalf("template %q has invalid kind %q", tp.TemplateID, tp.Kind)
		}
		for _, f := range tp.Fields {
			if f.Key == "" || !f.Type.Valid() {
				t.Fatalf("template %q has invalid field %+v", tp.TemplateID, f)
			}
			if f.Type == FieldEnum && len(f.Options) == 0 {
				t.Fatalf("template %q enum field %q has no options", tp.TemplateID, f.Key)
			}
		}
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd shared/go-common && go test ./domain/ -run TestTemplates -v`
Expected: FAIL — undefined `Templates`, `TemplateID`.

- [ ] **Step 4: Write minimal implementation**

```go
// shared/go-common/domain/templates.go
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd shared/go-common && go test ./domain/ -run TestTemplates -v`
Expected: PASS

- [ ] **Step 6: Run the whole domain package + format**

Run: `cd shared/go-common && gofmt -w domain/ && go test ./domain/...`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add shared/go-common/domain/templates.go shared/go-common/domain/templates.json shared/go-common/domain/templates_test.go
git commit -m "feat: embedded tracker-template catalog"
```

---

## Section B — Store layer

**Files in this section:**

- Modify: `shared/go-common/store/store.go` — extend `TableNames`/`Stores`, add generic `getItem[T]`/`queryItems[T]` + cursor helpers
- Create: `shared/go-common/store/receiver.go` + `receiver_test.go`
- Create: `shared/go-common/store/tracker.go` + `tracker_test.go`
- Create: `shared/go-common/store/event.go` + `event_test.go`
- Modify: `shared/go-common/store/dynamotest/dynamotest.go` — create the 3 new tables + GSIs
- Create: `shared/go-common/store/cursor_test.go`

**Section gate (acceptance criteria):**

- `Stores` exposes `Receivers`, `Trackers`, `Events`; `TableNames` has `Receivers`, `Trackers`, `Events`.
- Generic `getItem[T]` returns `ErrNotFound` on a missing item; `queryItems[T]` unmarshals a list.
- `EncodeCursor`/`DecodeCursor` round-trip an all-string key map.
- ReceiverStore/TrackerStore: Put, Get (ErrNotFound), list (archived hidden), Archive.
- EventStore: Put, Get, ListByTracker newest-first with a working cursor + `from`/`to` range, Update, Delete.
- `cd shared/go-common && go test ./store/...` passes (Docker required).

---

### Task B1: Extend Stores + generic helpers + cursor

**Files:**

- Modify: `shared/go-common/store/store.go`
- Test: `shared/go-common/store/cursor_test.go`

- [ ] **Step 1: Write the failing test**

```go
// shared/go-common/store/cursor_test.go
package store

import (
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func TestCursor_roundTrip(t *testing.T) {
	lek := map[string]types.AttributeValue{
		"tracker_id":  &types.AttributeValueMemberS{Value: "tr1"},
		"event_id":    &types.AttributeValueMemberS{Value: "ev1"},
		"occurred_at": &types.AttributeValueMemberS{Value: "2026-06-12T14:30:00Z"},
	}
	cur, err := EncodeCursor(lek)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	if cur == "" {
		t.Fatal("expected non-empty cursor")
	}
	got, err := DecodeCursor(cur)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got) != 3 {
		t.Fatalf("expected 3 keys, got %d", len(got))
	}
	if s, ok := got["event_id"].(*types.AttributeValueMemberS); !ok || s.Value != "ev1" {
		t.Fatalf("event_id not preserved: %+v", got["event_id"])
	}
}

func TestCursor_emptyInputs(t *testing.T) {
	cur, err := EncodeCursor(nil)
	if err != nil || cur != "" {
		t.Fatalf("nil LEK should encode to empty string, got %q err %v", cur, err)
	}
	got, err := DecodeCursor("")
	if err != nil || got != nil {
		t.Fatalf("empty cursor should decode to nil, got %+v err %v", got, err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shared/go-common && go test ./store/ -run TestCursor -v`
Expected: FAIL — undefined `EncodeCursor`/`DecodeCursor`.

- [ ] **Step 3: Edit `store.go`**

Replace the `TableNames` struct and `Stores` struct and `New` function, and add helpers. The full new content of the relevant parts:

```go
// TableNames holds every table name the stores need.
type TableNames struct {
	Users       string
	CareGroups  string
	Memberships string
	Invitations string
	Receivers   string
	Trackers    string
	Events      string
}

// Stores aggregates the per-entity repositories and owns cross-table transactions.
type Stores struct {
	client *dynamodb.Client
	names  TableNames

	Users       *UserStore
	CareGroups  *CareGroupStore
	Memberships *MembershipStore
	Invitations *InvitationStore
	Receivers   *ReceiverStore
	Trackers    *TrackerStore
	Events      *EventStore
}

const (
	groupIndex    = "group-index"
	emailIndex    = "email-index"
	receiverIndex = "receiver-index"
	timeIndex     = "time-index"
)

// New builds Stores from a DynamoDB client and table names.
func New(client *dynamodb.Client, names TableNames) *Stores {
	return &Stores{
		client:      client,
		names:       names,
		Users:       &UserStore{client: client, table: names.Users},
		CareGroups:  &CareGroupStore{client: client, table: names.CareGroups},
		Memberships: &MembershipStore{client: client, table: names.Memberships},
		Invitations: &InvitationStore{client: client, table: names.Invitations},
		Receivers:   &ReceiverStore{client: client, table: names.Receivers},
		Trackers:    &TrackerStore{client: client, table: names.Trackers},
		Events:      &EventStore{client: client, table: names.Events},
	}
}
```

Add these imports to `store.go` (`encoding/base64`, `encoding/json`, the attributevalue + dynamodb types packages) and append the helpers:

```go
// getItem fetches a single item by key and unmarshals it into T. Returns
// ErrNotFound when no item exists.
func getItem[T any](ctx context.Context, client *dynamodb.Client, table string, key map[string]types.AttributeValue) (T, error) {
	var zero T
	out, err := client.GetItem(ctx, &dynamodb.GetItemInput{TableName: aws.String(table), Key: key})
	if err != nil {
		return zero, err
	}
	if out.Item == nil {
		return zero, ErrNotFound
	}
	var v T
	if err := attributevalue.UnmarshalMap(out.Item, &v); err != nil {
		return zero, err
	}
	return v, nil
}

// queryItems runs a Query and unmarshals all items into []T.
func queryItems[T any](ctx context.Context, client *dynamodb.Client, in *dynamodb.QueryInput) ([]T, error) {
	out, err := client.Query(ctx, in)
	if err != nil {
		return nil, err
	}
	var vs []T
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &vs); err != nil {
		return nil, err
	}
	return vs, nil
}

// EncodeCursor serializes a DynamoDB LastEvaluatedKey to an opaque base64 string.
// It assumes all key attributes are strings (true for our event keys:
// tracker_id, event_id, occurred_at).
func EncodeCursor(lek map[string]types.AttributeValue) (string, error) {
	if len(lek) == 0 {
		return "", nil
	}
	var m map[string]any
	if err := attributevalue.UnmarshalMap(lek, &m); err != nil {
		return "", err
	}
	b, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// DecodeCursor reverses EncodeCursor. An empty string decodes to a nil key.
func DecodeCursor(s string) (map[string]types.AttributeValue, error) {
	if s == "" {
		return nil, nil
	}
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	return attributevalue.MarshalMap(m)
}
```

The required import block for `store.go` becomes:

```go
import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shared/go-common && go test ./store/ -run TestCursor -v`
Expected: PASS (this test does not need Docker)

- [ ] **Step 5: Commit**

```bash
git add shared/go-common/store/store.go shared/go-common/store/cursor_test.go
git commit -m "feat: extend stores with care tables, generic helpers, cursor"
```

---

### Task B2: dynamotest tables for receiver/tracker/event

**Files:**

- Modify: `shared/go-common/store/dynamotest/dynamotest.go`

- [ ] **Step 1: Add the three table names in `Start`**

In the `names := store.TableNames{...}` literal, add:

```go
	names := store.TableNames{
		Users:       "test-user",
		CareGroups:  "test-care-group",
		Memberships: "test-membership",
		Invitations: "test-invitation",
		Receivers:   "test-receiver",
		Trackers:    "test-tracker",
		Events:      "test-event",
	}
```

- [ ] **Step 2: Add the three `mustCreate` calls at the end of `createTables`**

```go
	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Receivers),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("receiver_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("created_at"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("receiver_id"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("group-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("created_at"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Trackers),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("tracker_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("receiver_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("created_at"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("tracker_id"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("receiver-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("receiver_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("created_at"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Events),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("tracker_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("event_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("occurred_at"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("tracker_id"), KeyType: types.KeyTypeHash},
			{AttributeName: aws.String("event_id"), KeyType: types.KeyTypeRange},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("time-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("tracker_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("occurred_at"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})
```

- [ ] **Step 3: Verify it compiles (the test package builds)**

Run: `cd shared/go-common && go build ./...`
Expected: builds clean (stores referenced next exist after B3/B4; if building before them, this step is deferred to end of B4).

- [ ] **Step 4: Commit**

```bash
git add shared/go-common/store/dynamotest/dynamotest.go
git commit -m "test: dynamotest tables for receiver/tracker/event"
```

---

### Task B3: ReceiverStore

**Files:**

- Create: `shared/go-common/store/receiver.go`
- Test: `shared/go-common/store/receiver_test.go`

- [ ] **Step 1: Write the failing test**

```go
// shared/go-common/store/receiver_test.go
package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestReceiverStore_putGetListArchive(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()

	r1 := domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedBy: "u1", CreatedAt: now}
	r2 := domain.Receiver{ReceiverID: "r2", CareGroupID: "g1", Name: "Dad", CreatedBy: "u1", CreatedAt: now.Add(time.Second)}
	for _, r := range []domain.Receiver{r1, r2} {
		if err := s.Receivers.Put(ctx, r); err != nil {
			t.Fatalf("put %s: %v", r.ReceiverID, err)
		}
	}

	got, err := s.Receivers.Get(ctx, "r1")
	if err != nil || got.Name != "Mom" {
		t.Fatalf("get r1: %+v err %v", got, err)
	}

	if _, err := s.Receivers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	list, err := s.Receivers.ListByGroup(ctx, "g1")
	if err != nil || len(list) != 2 {
		t.Fatalf("list g1: %d err %v", len(list), err)
	}

	if err := s.Receivers.Archive(ctx, "r1"); err != nil {
		t.Fatalf("archive r1: %v", err)
	}
	list, _ = s.Receivers.ListByGroup(ctx, "g1")
	if len(list) != 1 || list[0].ReceiverID != "r2" {
		t.Fatalf("archived receiver should be hidden, got %+v", list)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shared/go-common && go test ./store/ -run TestReceiverStore -v`
Expected: FAIL — undefined `ReceiverStore`.

- [ ] **Step 3: Write minimal implementation**

```go
// shared/go-common/store/receiver.go
package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type ReceiverStore struct {
	client *dynamodb.Client
	table  string
}

func (s *ReceiverStore) Put(ctx context.Context, r domain.Receiver) error {
	item, err := attributevalue.MarshalMap(r)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *ReceiverStore) Get(ctx context.Context, id string) (domain.Receiver, error) {
	return getItem[domain.Receiver](ctx, s.client, s.table, map[string]types.AttributeValue{
		"receiver_id": &types.AttributeValueMemberS{Value: id},
	})
}

// ListByGroup returns the non-archived receivers in a group, oldest-first.
func (s *ReceiverStore) ListByGroup(ctx context.Context, careGroupID string) ([]domain.Receiver, error) {
	return queryItems[domain.Receiver](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(groupIndex),
		KeyConditionExpression: aws.String("care_group_id = :g"),
		FilterExpression:       aws.String("archived = :f"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":g": &types.AttributeValueMemberS{Value: careGroupID},
			":f": &types.AttributeValueMemberBOOL{Value: false},
		},
	})
}

// Archive soft-deletes a receiver. Get/list filters hide archived rows; events
// and trackers are preserved.
func (s *ReceiverStore) Archive(ctx context.Context, id string) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:        aws.String(s.table),
		Key:              map[string]types.AttributeValue{"receiver_id": &types.AttributeValueMemberS{Value: id}},
		UpdateExpression: aws.String("SET archived = :t"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t": &types.AttributeValueMemberBOOL{Value: true},
		},
		ConditionExpression: aws.String("attribute_exists(receiver_id)"),
	})
	return err
}

// Update overwrites the mutable fields (name, date_of_birth) of an existing
// receiver. The caller has already loaded and authorized the row.
func (s *ReceiverStore) Update(ctx context.Context, r domain.Receiver) error {
	item, err := attributevalue.MarshalMap(r)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_exists(receiver_id)"),
	})
	return err
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shared/go-common && go test ./store/ -run TestReceiverStore -v`
Expected: PASS (Docker required)

- [ ] **Step 5: Commit**

```bash
git add shared/go-common/store/receiver.go shared/go-common/store/receiver_test.go
git commit -m "feat: receiver store"
```

---

### Task B4: TrackerStore

**Files:**

- Create: `shared/go-common/store/tracker.go`
- Test: `shared/go-common/store/tracker_test.go`

- [ ] **Step 1: Write the failing test**

```go
// shared/go-common/store/tracker_test.go
package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestTrackerStore_putGetListArchive(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC()

	tr := domain.Tracker{
		TrackerID: "tr1", ReceiverID: "r1", CareGroupID: "g1", Name: "Weight",
		Kind: domain.KindMeasurement, CreatedBy: "u1", CreatedAt: now,
		Fields: []domain.Field{{Key: "weight", Label: "Weight", Type: domain.FieldNumber, Required: true}},
	}
	if err := s.Trackers.Put(ctx, tr); err != nil {
		t.Fatalf("put: %v", err)
	}

	got, err := s.Trackers.Get(ctx, "tr1")
	if err != nil || got.Name != "Weight" || len(got.Fields) != 1 || got.Fields[0].Key != "weight" {
		t.Fatalf("get tr1: %+v err %v", got, err)
	}
	if _, err := s.Trackers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	list, err := s.Trackers.ListByReceiver(ctx, "r1")
	if err != nil || len(list) != 1 {
		t.Fatalf("list r1: %d err %v", len(list), err)
	}

	if err := s.Trackers.Archive(ctx, "tr1"); err != nil {
		t.Fatalf("archive: %v", err)
	}
	list, _ = s.Trackers.ListByReceiver(ctx, "r1")
	if len(list) != 0 {
		t.Fatalf("archived tracker should be hidden, got %+v", list)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shared/go-common && go test ./store/ -run TestTrackerStore -v`
Expected: FAIL — undefined `TrackerStore`.

- [ ] **Step 3: Write minimal implementation**

```go
// shared/go-common/store/tracker.go
package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type TrackerStore struct {
	client *dynamodb.Client
	table  string
}

func (s *TrackerStore) Put(ctx context.Context, tr domain.Tracker) error {
	item, err := attributevalue.MarshalMap(tr)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *TrackerStore) Get(ctx context.Context, id string) (domain.Tracker, error) {
	return getItem[domain.Tracker](ctx, s.client, s.table, map[string]types.AttributeValue{
		"tracker_id": &types.AttributeValueMemberS{Value: id},
	})
}

// ListByReceiver returns the non-archived trackers for a receiver, oldest-first.
func (s *TrackerStore) ListByReceiver(ctx context.Context, receiverID string) ([]domain.Tracker, error) {
	return queryItems[domain.Tracker](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(receiverIndex),
		KeyConditionExpression: aws.String("receiver_id = :r"),
		FilterExpression:       aws.String("archived = :f"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r": &types.AttributeValueMemberS{Value: receiverID},
			":f": &types.AttributeValueMemberBOOL{Value: false},
		},
	})
}

func (s *TrackerStore) Archive(ctx context.Context, id string) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:        aws.String(s.table),
		Key:              map[string]types.AttributeValue{"tracker_id": &types.AttributeValueMemberS{Value: id}},
		UpdateExpression: aws.String("SET archived = :t"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t": &types.AttributeValueMemberBOOL{Value: true},
		},
		ConditionExpression: aws.String("attribute_exists(tracker_id)"),
	})
	return err
}

// Update overwrites mutable fields (name/icon/color/fields) of an existing
// tracker. The caller has already loaded and authorized the row, so denormalized
// receiver_id/care_group_id are carried through unchanged.
func (s *TrackerStore) Update(ctx context.Context, tr domain.Tracker) error {
	item, err := attributevalue.MarshalMap(tr)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_exists(tracker_id)"),
	})
	return err
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shared/go-common && go test ./store/ -run TestTrackerStore -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shared/go-common/store/tracker.go shared/go-common/store/tracker_test.go
git commit -m "feat: tracker store"
```

---

### Task B5: EventStore (with pagination + range)

**Files:**

- Create: `shared/go-common/store/event.go`
- Test: `shared/go-common/store/event_test.go`

- [ ] **Step 1: Write the failing test**

```go
// shared/go-common/store/event_test.go
package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func seedEvent(t *testing.T, s *store.Stores, id string, at time.Time) {
	t.Helper()
	e := domain.Event{
		TrackerID: "tr1", EventID: id, CareGroupID: "g1", ReceiverID: "r1",
		Values: map[string]any{"weight": 170.0}, OccurredAt: at, LoggedBy: "u1", CreatedAt: at,
	}
	if err := s.Events.Put(context.Background(), e); err != nil {
		t.Fatalf("seed %s: %v", id, err)
	}
}

func TestEventStore_putGetUpdateDelete(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	seedEvent(t, s, "e1", time.Now().UTC())

	got, err := s.Events.Get(ctx, "tr1", "e1")
	if err != nil || got.Values["weight"] != 170.0 {
		t.Fatalf("get: %+v err %v", got, err)
	}

	got.Values["weight"] = 168.0
	if err := s.Events.Update(ctx, got); err != nil {
		t.Fatalf("update: %v", err)
	}
	reread, _ := s.Events.Get(ctx, "tr1", "e1")
	if reread.Values["weight"] != 168.0 {
		t.Fatalf("update not persisted: %+v", reread)
	}

	if err := s.Events.Delete(ctx, "tr1", "e1"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.Events.Get(ctx, "tr1", "e1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("expected ErrNotFound after delete, got %v", err)
	}
}

func TestEventStore_listNewestFirstAndPaginate(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	base := time.Date(2026, 6, 12, 9, 0, 0, 0, time.UTC)
	seedEvent(t, s, "e1", base)
	seedEvent(t, s, "e2", base.Add(time.Hour))
	seedEvent(t, s, "e3", base.Add(2*time.Hour))

	page1, cur, err := s.Events.ListByTracker(ctx, "tr1", 2, "", nil, nil)
	if err != nil || len(page1) != 2 {
		t.Fatalf("page1: %d err %v", len(page1), err)
	}
	if page1[0].EventID != "e3" || page1[1].EventID != "e2" {
		t.Fatalf("expected newest-first e3,e2, got %s,%s", page1[0].EventID, page1[1].EventID)
	}
	if cur == "" {
		t.Fatal("expected a cursor for the next page")
	}
	page2, cur2, err := s.Events.ListByTracker(ctx, "tr1", 2, cur, nil, nil)
	if err != nil || len(page2) != 1 || page2[0].EventID != "e1" {
		t.Fatalf("page2: %+v err %v", page2, err)
	}
	if cur2 != "" {
		t.Fatalf("expected empty cursor at end, got %q", cur2)
	}
}

func TestEventStore_listRange(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	base := time.Date(2026, 6, 12, 9, 0, 0, 0, time.UTC)
	seedEvent(t, s, "e1", base)
	seedEvent(t, s, "e2", base.Add(time.Hour))
	seedEvent(t, s, "e3", base.Add(2*time.Hour))

	from := base.Add(30 * time.Minute)
	to := base.Add(90 * time.Minute)
	got, _, err := s.Events.ListByTracker(ctx, "tr1", 10, "", &from, &to)
	if err != nil || len(got) != 1 || got[0].EventID != "e2" {
		t.Fatalf("range expected only e2, got %+v err %v", got, err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shared/go-common && go test ./store/ -run TestEventStore -v`
Expected: FAIL — undefined `EventStore`.

- [ ] **Step 3: Write minimal implementation**

```go
// shared/go-common/store/event.go
package store

import (
	"context"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type EventStore struct {
	client *dynamodb.Client
	table  string
}

func eventKey(trackerID, eventID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{
		"tracker_id": &types.AttributeValueMemberS{Value: trackerID},
		"event_id":   &types.AttributeValueMemberS{Value: eventID},
	}
}

func (s *EventStore) Put(ctx context.Context, e domain.Event) error {
	item, err := attributevalue.MarshalMap(e)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *EventStore) Get(ctx context.Context, trackerID, eventID string) (domain.Event, error) {
	return getItem[domain.Event](ctx, s.client, s.table, eventKey(trackerID, eventID))
}

// Update overwrites an existing event, asserting it still exists.
func (s *EventStore) Update(ctx context.Context, e domain.Event) error {
	item, err := attributevalue.MarshalMap(e)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_exists(event_id)"),
	})
	return err
}

func (s *EventStore) Delete(ctx context.Context, trackerID, eventID string) error {
	_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(s.table),
		Key:       eventKey(trackerID, eventID),
	})
	return err
}

// ListByTracker returns events newest-first via the time-index, paginated by an
// opaque cursor. from/to (inclusive) bound occurred_at; nil means unbounded.
// occurred_at is stored by the attributevalue marshaler as RFC3339Nano, so the
// range comparison strings use the same format.
func (s *EventStore) ListByTracker(ctx context.Context, trackerID string, limit int32, cursor string, from, to *time.Time) ([]domain.Event, string, error) {
	keyCond := "tracker_id = :t"
	vals := map[string]types.AttributeValue{":t": &types.AttributeValueMemberS{Value: trackerID}}
	switch {
	case from != nil && to != nil:
		keyCond += " AND occurred_at BETWEEN :from AND :to"
		vals[":from"] = &types.AttributeValueMemberS{Value: from.UTC().Format(time.RFC3339Nano)}
		vals[":to"] = &types.AttributeValueMemberS{Value: to.UTC().Format(time.RFC3339Nano)}
	case from != nil:
		keyCond += " AND occurred_at >= :from"
		vals[":from"] = &types.AttributeValueMemberS{Value: from.UTC().Format(time.RFC3339Nano)}
	case to != nil:
		keyCond += " AND occurred_at <= :to"
		vals[":to"] = &types.AttributeValueMemberS{Value: to.UTC().Format(time.RFC3339Nano)}
	}

	start, err := DecodeCursor(cursor)
	if err != nil {
		return nil, "", err
	}
	in := &dynamodb.QueryInput{
		TableName:                 aws.String(s.table),
		IndexName:                 aws.String(timeIndex),
		KeyConditionExpression:    aws.String(keyCond),
		ExpressionAttributeValues: vals,
		ScanIndexForward:          aws.Bool(false), // newest first
		ExclusiveStartKey:         start,
	}
	if limit > 0 {
		in.Limit = aws.Int32(limit)
	}
	out, err := s.client.Query(ctx, in)
	if err != nil {
		return nil, "", err
	}
	var events []domain.Event
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &events); err != nil {
		return nil, "", err
	}
	next, err := EncodeCursor(out.LastEvaluatedKey)
	if err != nil {
		return nil, "", err
	}
	return events, next, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shared/go-common && go test ./store/ -run TestEventStore -v`
Expected: PASS

- [ ] **Step 5: Run the whole store + domain suites, format**

Run: `cd shared/go-common && gofmt -w ./... && go test ./...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add shared/go-common/store/event.go shared/go-common/store/event_test.go
git commit -m "feat: event store with pagination and time range"
```

---

## Section C — OpenAPI contract + codegen

**Files in this section:**

- Modify: `shared/openapi/openapi.yaml` — add care schemas + paths
- Regenerate: `shared/types-go/caregiverapi/types.gen.go`, the TS client, and the Swift spec copy

**Section gate (acceptance criteria):**

- New schemas: `Field`, `Threshold`, `TrackerKind`, `FieldType`, `Receiver`, `Tracker`, `Event`, `Breach`, `TrackerTemplate`, `EventList`, plus create/update request bodies.
- New paths for all 16 B3a endpoints with the right auth responses (401/403/404) referencing existing `responses`.
- `cd shared/types-go && make codegen` runs clean and the regenerated files are committed.
- `pnpm exec prettier --check` passes on the YAML (run `--write` first).

---

### Task C1: Author the contract and regenerate

**Files:**

- Modify: `shared/openapi/openapi.yaml`

- [ ] **Step 1: Add the schemas** under `components.schemas` (after the existing `AcceptInvitationResponse`, before `Error`):

```yaml
TrackerKind:
  type: string
  enum: [event, measurement, scheduled]
FieldType:
  type: string
  enum: [number, text, boolean, enum, datetime]
Threshold:
  type: object
  properties:
    min: { type: number }
    max: { type: number }
Field:
  type: object
  required: [key, label, type]
  properties:
    key: { type: string }
    label: { type: string }
    type: { $ref: '#/components/schemas/FieldType' }
    unit: { type: string }
    required: { type: boolean }
    options:
      type: array
      items: { type: string }
    threshold: { $ref: '#/components/schemas/Threshold' }
Receiver:
  type: object
  required: [receiver_id, care_group_id, name, created_by, created_at, archived]
  properties:
    receiver_id: { type: string }
    care_group_id: { type: string }
    name: { type: string }
    date_of_birth: { type: string }
    created_by: { type: string }
    created_at: { type: string, format: date-time }
    archived: { type: boolean }
CreateReceiverRequest:
  type: object
  required: [name]
  properties:
    name: { type: string, minLength: 1, maxLength: 200 }
    date_of_birth: { type: string }
UpdateReceiverRequest:
  type: object
  properties:
    name: { type: string, minLength: 1, maxLength: 200 }
    date_of_birth: { type: string }
Tracker:
  type: object
  required:
    [tracker_id, receiver_id, care_group_id, name, kind, fields, created_by, created_at, archived]
  properties:
    tracker_id: { type: string }
    receiver_id: { type: string }
    care_group_id: { type: string }
    name: { type: string }
    kind: { $ref: '#/components/schemas/TrackerKind' }
    icon: { type: string }
    color: { type: string }
    fields:
      type: array
      items: { $ref: '#/components/schemas/Field' }
    created_by: { type: string }
    created_at: { type: string, format: date-time }
    archived: { type: boolean }
TrackerWrite:
  type: object
  required: [name, kind, fields]
  properties:
    name: { type: string, minLength: 1, maxLength: 200 }
    kind: { $ref: '#/components/schemas/TrackerKind' }
    icon: { type: string }
    color: { type: string }
    fields:
      type: array
      items: { $ref: '#/components/schemas/Field' }
TrackerTemplate:
  type: object
  required: [template_id, name, kind, fields]
  properties:
    template_id: { type: string }
    name: { type: string }
    kind: { $ref: '#/components/schemas/TrackerKind' }
    icon: { type: string }
    color: { type: string }
    fields:
      type: array
      items: { $ref: '#/components/schemas/Field' }
Breach:
  type: object
  required: [key, value, bound, limit]
  properties:
    key: { type: string }
    value: { type: number }
    bound: { type: string, enum: [min, max] }
    limit: { type: number }
Event:
  type: object
  required:
    [tracker_id, event_id, care_group_id, receiver_id, values, occurred_at, logged_by, created_at]
  properties:
    tracker_id: { type: string }
    event_id: { type: string }
    care_group_id: { type: string }
    receiver_id: { type: string }
    values:
      type: object
      additionalProperties: true
    note: { type: string }
    occurred_at: { type: string, format: date-time }
    logged_by: { type: string }
    created_at: { type: string, format: date-time }
    breaches:
      type: array
      items: { $ref: '#/components/schemas/Breach' }
EventWrite:
  type: object
  required: [values]
  properties:
    occurred_at: { type: string, format: date-time }
    values:
      type: object
      additionalProperties: true
    note: { type: string }
EventList:
  type: object
  required: [items]
  properties:
    items:
      type: array
      items: { $ref: '#/components/schemas/Event' }
    next_cursor: { type: string }
```

- [ ] **Step 2: Add the paths** under `paths` (after the existing `/invitations/{token}/accept` block). This adds all 16 routes:

```yaml
/receivers:
  get:
    operationId: listReceivers
    summary: List receivers across the caller's groups (optionally one group)
    parameters:
      - { name: careGroupId, in: query, required: false, schema: { type: string } }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema:
              type: array
              items: { $ref: '#/components/schemas/Receiver' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
/care-groups/{careGroupId}/receivers:
  post:
    operationId: createReceiver
    summary: Add a receiver to a care group (admin only)
    parameters:
      - { name: careGroupId, in: path, required: true, schema: { type: string } }
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/CreateReceiverRequest' }
    responses:
      '201':
        description: Created
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Receiver' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
/receivers/{receiverId}:
  get:
    operationId: getReceiver
    summary: Get a receiver
    parameters:
      - { name: receiverId, in: path, required: true, schema: { type: string } }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Receiver' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  patch:
    operationId: updateReceiver
    summary: Update a receiver (admin only)
    parameters:
      - { name: receiverId, in: path, required: true, schema: { type: string } }
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/UpdateReceiverRequest' }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Receiver' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  delete:
    operationId: archiveReceiver
    summary: Archive a receiver (admin only)
    parameters:
      - { name: receiverId, in: path, required: true, schema: { type: string } }
    responses:
      '204': { description: No Content }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
/receivers/{receiverId}/trackers:
  get:
    operationId: listTrackers
    summary: List a receiver's trackers
    parameters:
      - { name: receiverId, in: path, required: true, schema: { type: string } }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema:
              type: array
              items: { $ref: '#/components/schemas/Tracker' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  post:
    operationId: createTracker
    summary: Create a tracker for a receiver (admin only)
    parameters:
      - { name: receiverId, in: path, required: true, schema: { type: string } }
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/TrackerWrite' }
    responses:
      '201':
        description: Created
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Tracker' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
/trackers/{trackerId}:
  get:
    operationId: getTracker
    summary: Get a tracker
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Tracker' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  patch:
    operationId: updateTracker
    summary: Update a tracker (admin only)
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/TrackerWrite' }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Tracker' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  delete:
    operationId: archiveTracker
    summary: Archive a tracker (admin only)
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
    responses:
      '204': { description: No Content }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
/trackers/{trackerId}/events:
  get:
    operationId: listEvents
    summary: List a tracker's events, newest first (paginated)
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
      - {
          name: limit,
          in: query,
          required: false,
          schema: { type: integer, minimum: 1, maximum: 100 },
        }
      - { name: cursor, in: query, required: false, schema: { type: string } }
      - { name: from, in: query, required: false, schema: { type: string, format: date-time } }
      - { name: to, in: query, required: false, schema: { type: string, format: date-time } }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/EventList' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  post:
    operationId: logEvent
    summary: Log an event against a tracker
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/EventWrite' }
    responses:
      '201':
        description: Created
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Event' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
/trackers/{trackerId}/events/{eventId}:
  get:
    operationId: getEvent
    summary: Get a single event
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
      - { name: eventId, in: path, required: true, schema: { type: string } }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Event' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  patch:
    operationId: updateEvent
    summary: Edit a logged event
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
      - { name: eventId, in: path, required: true, schema: { type: string } }
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/EventWrite' }
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Event' }
      '400': { $ref: '#/components/responses/BadRequest' }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
  delete:
    operationId: deleteEvent
    summary: Delete a logged event
    parameters:
      - { name: trackerId, in: path, required: true, schema: { type: string } }
      - { name: eventId, in: path, required: true, schema: { type: string } }
    responses:
      '204': { description: No Content }
      '401': { $ref: '#/components/responses/Unauthorized' }
      '403': { $ref: '#/components/responses/Forbidden' }
      '404': { $ref: '#/components/responses/NotFound' }
/tracker-templates:
  get:
    operationId: listTrackerTemplates
    summary: List the seeded tracker-template catalog
    responses:
      '200':
        description: OK
        content:
          application/json:
            schema:
              type: array
              items: { $ref: '#/components/schemas/TrackerTemplate' }
      '401': { $ref: '#/components/responses/Unauthorized' }
```

- [ ] **Step 3: Regenerate all three clients**

Reproduce exactly what the lefthook `openapi-codegen` hook runs (from the repo root):

```bash
pnpm --filter @caregiver/types-ts run build
(cd shared/types-go && make codegen)
cp shared/openapi/openapi.yaml shared/types-swift/Sources/CaregiverAPI/openapi.yaml
```

Expected: rewrites `shared/types-ts/src/schema.gen.ts` (+ `dist/`), `shared/types-go/caregiverapi/types.gen.go`, and the Swift spec copy with no errors.

- [ ] **Step 4: Format + verify the contract builds**

Run: `pnpm exec prettier --write shared/openapi/openapi.yaml && cd shared/types-go && go build ./...`
Expected: prettier rewrites YAML; `types.gen.go` compiles.

- [ ] **Step 5: Commit the contract + generated files**

```bash
git add shared/openapi/openapi.yaml shared/types-go/ shared/types-ts/ shared/types-swift/
git commit -m "feat: openapi contract for receivers, trackers, events"
```

---

## Section D — HTTP handlers + route wiring

**Files in this section:**

- Create: `api/internal/handlers/receivers.go` + `receivers_test.go`
- Create: `api/internal/handlers/trackers.go` + `trackers_test.go`
- Create: `api/internal/handlers/events.go` + `events_test.go`
- Create: `api/internal/handlers/templates.go` + `templates_test.go`
- Modify: `api/cmd/lambda/mux.go` — construct handlers, wire routes, add env table names
- Modify: `api/internal/handlers/isolation_test.go` — extend the isolation suite

**Section gate (acceptance criteria):**

- Receivers: list (member), create (admin→201, caregiver→403), get/patch/delete with cross-group 403.
- Trackers: create resolves receiver→group, admin-gated; list/get member-gated; archive admin-gated.
- Events: log validates against tracker fields (400 on bad payload), member-gated; list paginates with `breaches` on read; get/patch/delete member-gated.
- Templates: returns the embedded catalog.
- `mux.go` wires all routes through `authn.Wrap`; `newStores` reads the new env table names.
- Isolation suite: a member of group 1 gets 403/404 on every new endpoint targeting group 2.
- `cd api && go test ./...` passes (Docker required).

---

### Task D1: Receivers handler

**Files:**

- Create: `api/internal/handlers/receivers.go`
- Test: `api/internal/handlers/receivers_test.go`

- [ ] **Step 1: Write the failing test**

```go
// api/internal/handlers/receivers_test.go
package handlers_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func TestReceivers_createRequiresAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewReceivers(s)

	// caregiver -> 403
	req := httptest.NewRequest(http.MethodPost, "/care-groups/g1/receivers", strings.NewReader(`{"name":"Mom"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver create should be 403, got %d", rec.Code)
	}

	// admin -> 201
	req = httptest.NewRequest(http.MethodPost, "/care-groups/g1/receivers", strings.NewReader(`{"name":"Mom"}`))
	req.SetPathValue("careGroupId", "g1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec = httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("admin create should be 201, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"name":"Mom"`) {
		t.Fatalf("expected receiver body, got %s", rec.Body.String())
	}
}

func TestReceivers_getMemberGated(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	_ = s.Receivers.Put(ctx, domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewReceivers(s)

	// non-member -> 403
	req := httptest.NewRequest(http.MethodGet, "/receivers/r1", nil)
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Get(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member get should be 403, got %d", rec.Code)
	}

	// member -> 200
	req = httptest.NewRequest(http.MethodGet, "/receivers/r1", nil)
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec = httptest.NewRecorder()
	h.Get(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("member get should be 200, got %d", rec.Code)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd api && go test ./internal/handlers/ -run TestReceivers -v`
Expected: FAIL — undefined `handlers.NewReceivers`.

- [ ] **Step 3: Write minimal implementation**

```go
// api/internal/handlers/receivers.go
package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Receivers struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewReceivers(s *store.Stores) *Receivers {
	return &Receivers{stores: s, now: time.Now, newID: uuid.NewString}
}

func (h *Receivers) List(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	if ac == nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx := r.Context()
	groupID := r.URL.Query().Get("careGroupId")
	out := []domain.Receiver{}
	if groupID != "" {
		if !httpx.RequireMember(w, ac, groupID) {
			return
		}
		rs, err := h.stores.Receivers.ListByGroup(ctx, groupID)
		if err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, "list failed")
			return
		}
		out = append(out, rs...)
	} else {
		for gid := range ac.Memberships {
			rs, err := h.stores.Receivers.ListByGroup(ctx, gid)
			if err != nil {
				httpx.WriteError(w, http.StatusInternalServerError, "list failed")
				return
			}
			out = append(out, rs...)
		}
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Receivers) Create(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	groupID := r.PathValue("careGroupId")
	if !httpx.RequireAdmin(w, ac, groupID) {
		return
	}
	var req struct {
		Name        string `json:"name"`
		DateOfBirth string `json:"date_of_birth"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		httpx.WriteError(w, http.StatusBadRequest, "name is required")
		return
	}
	rec := domain.Receiver{
		ReceiverID: h.newID(), CareGroupID: groupID, Name: strings.TrimSpace(req.Name),
		DateOfBirth: strings.TrimSpace(req.DateOfBirth), CreatedBy: ac.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.Receivers.Put(r.Context(), rec); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, rec)
}

// load fetches a receiver and enforces membership; writes the error response and
// returns ok=false on any failure.
func (h *Receivers) load(w http.ResponseWriter, r *http.Request) (domain.Receiver, *auth.AuthContext, bool) {
	ac := auth.FromContext(r.Context())
	id := r.PathValue("receiverId")
	rec, err := h.stores.Receivers.Get(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) || (err == nil && rec.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "receiver not found")
		return domain.Receiver{}, nil, false
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return domain.Receiver{}, nil, false
	}
	if !httpx.RequireMember(w, ac, rec.CareGroupID) {
		return domain.Receiver{}, nil, false
	}
	return rec, ac, true
}

func (h *Receivers) Get(w http.ResponseWriter, r *http.Request) {
	rec, _, ok := h.load(w, r)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, rec)
}

func (h *Receivers) Update(w http.ResponseWriter, r *http.Request) {
	rec, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, rec.CareGroupID) {
		return
	}
	var req struct {
		Name        *string `json:"name"`
		DateOfBirth *string `json:"date_of_birth"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Name != nil {
		if strings.TrimSpace(*req.Name) == "" {
			httpx.WriteError(w, http.StatusBadRequest, "name cannot be empty")
			return
		}
		rec.Name = strings.TrimSpace(*req.Name)
	}
	if req.DateOfBirth != nil {
		rec.DateOfBirth = strings.TrimSpace(*req.DateOfBirth)
	}
	if err := h.stores.Receivers.Update(r.Context(), rec); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, rec)
}

func (h *Receivers) Archive(w http.ResponseWriter, r *http.Request) {
	rec, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, rec.CareGroupID) {
		return
	}
	if err := h.stores.Receivers.Archive(r.Context(), rec.ReceiverID); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "archive failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd api && go test ./internal/handlers/ -run TestReceivers -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add api/internal/handlers/receivers.go api/internal/handlers/receivers_test.go
git commit -m "feat: receivers handler"
```

---

### Task D2: Trackers handler

**Files:**

- Create: `api/internal/handlers/trackers.go`
- Test: `api/internal/handlers/trackers_test.go`

- [ ] **Step 1: Write the failing test**

```go
// api/internal/handlers/trackers_test.go
package handlers_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func TestTrackers_createResolvesGroupAndRequiresAdmin(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	_ = s.Receivers.Put(ctx, domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewTrackers(s)

	body := `{"name":"Weight","kind":"measurement","fields":[{"key":"weight","label":"Weight","type":"number","required":true}]}`

	// caregiver -> 403
	req := httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers", strings.NewReader(body))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver tracker create should be 403, got %d", rec.Code)
	}

	// admin -> 201
	req = httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers", strings.NewReader(body))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec = httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("admin tracker create should be 201, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"care_group_id":"g1"`) {
		t.Fatalf("tracker should denormalize care_group_id, got %s", rec.Body.String())
	}
}

func TestTrackers_createRejectsBadKind(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	_ = s.Receivers.Put(ctx, domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewTrackers(s)
	req := httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers",
		strings.NewReader(`{"name":"X","kind":"bogus","fields":[]}`))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("bad kind should be 400, got %d", rec.Code)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd api && go test ./internal/handlers/ -run TestTrackers -v`
Expected: FAIL — undefined `handlers.NewTrackers`.

- [ ] **Step 3: Write minimal implementation**

```go
// api/internal/handlers/trackers.go
package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Trackers struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewTrackers(s *store.Stores) *Trackers {
	return &Trackers{stores: s, now: time.Now, newID: uuid.NewString}
}

type trackerWrite struct {
	Name   string         `json:"name"`
	Kind   domain.TrackerKind `json:"kind"`
	Icon   string         `json:"icon"`
	Color  string         `json:"color"`
	Fields []domain.Field `json:"fields"`
}

// validFields checks the schema definition itself (not event values).
func validFields(fields []domain.Field) bool {
	seen := map[string]bool{}
	for _, f := range fields {
		if f.Key == "" || f.Label == "" || !f.Type.Valid() || seen[f.Key] {
			return false
		}
		if f.Type == domain.FieldEnum && len(f.Options) == 0 {
			return false
		}
		seen[f.Key] = true
	}
	return true
}

func (h *Trackers) ListByReceiver(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	recv, err := h.stores.Receivers.Get(r.Context(), r.PathValue("receiverId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && recv.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "receiver not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return
	}
	if !httpx.RequireMember(w, ac, recv.CareGroupID) {
		return
	}
	list, err := h.stores.Trackers.ListByReceiver(r.Context(), recv.ReceiverID)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "list failed")
		return
	}
	if list == nil {
		list = []domain.Tracker{}
	}
	httpx.WriteJSON(w, http.StatusOK, list)
}

func (h *Trackers) Create(w http.ResponseWriter, r *http.Request) {
	ac := auth.FromContext(r.Context())
	recv, err := h.stores.Receivers.Get(r.Context(), r.PathValue("receiverId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && recv.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "receiver not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return
	}
	if !httpx.RequireAdmin(w, ac, recv.CareGroupID) {
		return
	}
	var req trackerWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if strings.TrimSpace(req.Name) == "" || !req.Kind.Valid() || !validFields(req.Fields) {
		httpx.WriteError(w, http.StatusBadRequest, "name, a valid kind, and valid fields are required")
		return
	}
	tr := domain.Tracker{
		TrackerID: h.newID(), ReceiverID: recv.ReceiverID, CareGroupID: recv.CareGroupID,
		Name: strings.TrimSpace(req.Name), Kind: req.Kind, Icon: req.Icon, Color: req.Color,
		Fields: req.Fields, CreatedBy: ac.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.Trackers.Put(r.Context(), tr); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, tr)
}

func (h *Trackers) load(w http.ResponseWriter, r *http.Request) (domain.Tracker, *auth.AuthContext, bool) {
	ac := auth.FromContext(r.Context())
	tr, err := h.stores.Trackers.Get(r.Context(), r.PathValue("trackerId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && tr.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "tracker not found")
		return domain.Tracker{}, nil, false
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return domain.Tracker{}, nil, false
	}
	if !httpx.RequireMember(w, ac, tr.CareGroupID) {
		return domain.Tracker{}, nil, false
	}
	return tr, ac, true
}

func (h *Trackers) Get(w http.ResponseWriter, r *http.Request) {
	tr, _, ok := h.load(w, r)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, tr)
}

func (h *Trackers) Update(w http.ResponseWriter, r *http.Request) {
	tr, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, tr.CareGroupID) {
		return
	}
	var req trackerWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if strings.TrimSpace(req.Name) == "" || !req.Kind.Valid() || !validFields(req.Fields) {
		httpx.WriteError(w, http.StatusBadRequest, "name, a valid kind, and valid fields are required")
		return
	}
	tr.Name, tr.Kind, tr.Icon, tr.Color, tr.Fields = strings.TrimSpace(req.Name), req.Kind, req.Icon, req.Color, req.Fields
	if err := h.stores.Trackers.Update(r.Context(), tr); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, tr)
}

func (h *Trackers) Archive(w http.ResponseWriter, r *http.Request) {
	tr, ac, ok := h.load(w, r)
	if !ok {
		return
	}
	if !httpx.RequireAdmin(w, ac, tr.CareGroupID) {
		return
	}
	if err := h.stores.Trackers.Archive(r.Context(), tr.TrackerID); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "archive failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd api && go test ./internal/handlers/ -run TestTrackers -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add api/internal/handlers/trackers.go api/internal/handlers/trackers_test.go
git commit -m "feat: trackers handler"
```

---

### Task D3: Events handler

**Files:**

- Create: `api/internal/handlers/events.go`
- Test: `api/internal/handlers/events_test.go`

- [ ] **Step 1: Write the failing test**

```go
// api/internal/handlers/events_test.go
package handlers_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func seedTracker(t *testing.T, s interface {
	Put(context.Context, domain.Tracker) error
}) {
	t.Helper()
	max140 := 140.0
	tr := domain.Tracker{
		TrackerID: "tr1", ReceiverID: "r1", CareGroupID: "g1", Name: "BP",
		Kind: domain.KindMeasurement, CreatedAt: time.Now().UTC(),
		Fields: []domain.Field{
			{Key: "systolic", Label: "Systolic", Type: domain.FieldNumber, Required: true, Threshold: &domain.Threshold{Max: &max140}},
		},
	}
	if err := s.Put(context.Background(), tr); err != nil {
		t.Fatalf("seed tracker: %v", err)
	}
}

func TestEvents_logValidatesAndDenormalizes(t *testing.T) {
	s := dynamotest.Start(t)
	seedTracker(t, s.Trackers)
	h := handlers.NewEvents(s)

	// invalid: missing required systolic -> 400
	req := httptest.NewRequest(http.MethodPost, "/trackers/tr1/events", strings.NewReader(`{"values":{}}`))
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("missing required should be 400, got %d", rec.Code)
	}

	// valid -> 201, denormalized receiver/group, logged_by set
	req = httptest.NewRequest(http.MethodPost, "/trackers/tr1/events", strings.NewReader(`{"values":{"systolic":128}}`))
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec = httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("valid log should be 201, got %d: %s", rec.Code, rec.Body.String())
	}
	for _, want := range []string{`"receiver_id":"r1"`, `"care_group_id":"g1"`, `"logged_by":"u1"`} {
		if !strings.Contains(rec.Body.String(), want) {
			t.Fatalf("expected %s in %s", want, rec.Body.String())
		}
	}
}

func TestEvents_listReturnsBreaches(t *testing.T) {
	s := dynamotest.Start(t)
	seedTracker(t, s.Trackers)
	h := handlers.NewEvents(s)
	_ = s.Events.Put(context.Background(), domain.Event{
		TrackerID: "tr1", EventID: "e1", CareGroupID: "g1", ReceiverID: "r1",
		Values: map[string]any{"systolic": 162.0}, OccurredAt: time.Now().UTC(), LoggedBy: "u1", CreatedAt: time.Now().UTC(),
	})
	req := httptest.NewRequest(http.MethodGet, "/trackers/tr1/events", nil)
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.List(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"bound":"max"`) {
		t.Fatalf("expected breach in list body, got %d %s", rec.Code, rec.Body.String())
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd api && go test ./internal/handlers/ -run TestEvents -v`
Expected: FAIL — undefined `handlers.NewEvents`.

- [ ] **Step 3: Write minimal implementation**

```go
// api/internal/handlers/events.go
package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/auth"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

type Events struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewEvents(s *store.Stores) *Events {
	return &Events{stores: s, now: time.Now, newID: uuid.NewString}
}

// eventView wraps a stored event with the computed breaches for the response.
type eventView struct {
	domain.Event
	Breaches []domain.Breach `json:"breaches,omitempty"`
}

type eventWrite struct {
	OccurredAt *time.Time     `json:"occurred_at"`
	Values     map[string]any `json:"values"`
	Note       string         `json:"note"`
}

// trackerForRequest loads the tracker named in the path and enforces membership.
func (h *Events) trackerForRequest(w http.ResponseWriter, r *http.Request) (domain.Tracker, *auth.AuthContext, bool) {
	ac := auth.FromContext(r.Context())
	tr, err := h.stores.Trackers.Get(r.Context(), r.PathValue("trackerId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && tr.Archived) {
		httpx.WriteError(w, http.StatusNotFound, "tracker not found")
		return domain.Tracker{}, nil, false
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return domain.Tracker{}, nil, false
	}
	if !httpx.RequireMember(w, ac, tr.CareGroupID) {
		return domain.Tracker{}, nil, false
	}
	return tr, ac, true
}

func (h *Events) Create(w http.ResponseWriter, r *http.Request) {
	tr, ac, ok := h.trackerForRequest(w, r)
	if !ok {
		return
	}
	var req eventWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Values == nil {
		httpx.WriteError(w, http.StatusBadRequest, "values are required")
		return
	}
	if err := domain.ValidateValues(tr.Fields, req.Values); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	occurred := h.now().UTC()
	if req.OccurredAt != nil {
		occurred = req.OccurredAt.UTC()
	}
	e := domain.Event{
		TrackerID: tr.TrackerID, EventID: h.newID(), CareGroupID: tr.CareGroupID, ReceiverID: tr.ReceiverID,
		Values: req.Values, Note: req.Note, OccurredAt: occurred, LoggedBy: ac.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.Events.Put(r.Context(), e); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "log failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
}

func (h *Events) List(w http.ResponseWriter, r *http.Request) {
	tr, _, ok := h.trackerForRequest(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	limit := int32(50)
	if l := q.Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 100 {
			limit = int32(n)
		}
	}
	var from, to *time.Time
	if f := q.Get("from"); f != "" {
		if ts, err := time.Parse(time.RFC3339, f); err == nil {
			from = &ts
		}
	}
	if tt := q.Get("to"); tt != "" {
		if ts, err := time.Parse(time.RFC3339, tt); err == nil {
			to = &ts
		}
	}
	events, next, err := h.stores.Events.ListByTracker(r.Context(), tr.TrackerID, limit, q.Get("cursor"), from, to)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "list failed")
		return
	}
	items := make([]eventView, 0, len(events))
	for _, e := range events {
		items = append(items, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": next})
}

// loadEvent resolves the tracker (for authz + fields) and the addressed event.
func (h *Events) loadEvent(w http.ResponseWriter, r *http.Request) (domain.Tracker, domain.Event, bool) {
	tr, _, ok := h.trackerForRequest(w, r)
	if !ok {
		return domain.Tracker{}, domain.Event{}, false
	}
	e, err := h.stores.Events.Get(r.Context(), tr.TrackerID, r.PathValue("eventId"))
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "event not found")
		return domain.Tracker{}, domain.Event{}, false
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "lookup failed")
		return domain.Tracker{}, domain.Event{}, false
	}
	return tr, e, true
}

func (h *Events) Get(w http.ResponseWriter, r *http.Request) {
	tr, e, ok := h.loadEvent(w, r)
	if !ok {
		return
	}
	httpx.WriteJSON(w, http.StatusOK, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
}

func (h *Events) Update(w http.ResponseWriter, r *http.Request) {
	tr, e, ok := h.loadEvent(w, r)
	if !ok {
		return
	}
	var req eventWrite
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Values == nil {
		httpx.WriteError(w, http.StatusBadRequest, "values are required")
		return
	}
	if err := domain.ValidateValues(tr.Fields, req.Values); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	e.Values = req.Values
	e.Note = req.Note
	if req.OccurredAt != nil {
		e.OccurredAt = req.OccurredAt.UTC()
	}
	if err := h.stores.Events.Update(r.Context(), e); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "update failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, eventView{Event: e, Breaches: domain.Breaches(tr.Fields, e.Values)})
}

func (h *Events) Delete(w http.ResponseWriter, r *http.Request) {
	tr, e, ok := h.loadEvent(w, r)
	if !ok {
		return
	}
	if err := h.stores.Events.Delete(r.Context(), tr.TrackerID, e.EventID); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "delete failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd api && go test ./internal/handlers/ -run TestEvents -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add api/internal/handlers/events.go api/internal/handlers/events_test.go
git commit -m "feat: events handler with validation and breaches"
```

---

### Task D4: Templates handler

**Files:**

- Create: `api/internal/handlers/templates.go`
- Test: `api/internal/handlers/templates_test.go`

- [ ] **Step 1: Write the failing test**

```go
// api/internal/handlers/templates_test.go
package handlers_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

func TestTemplates_listReturnsCatalog(t *testing.T) {
	h := handlers.NewTemplates()
	req := httptest.NewRequest(http.MethodGet, "/tracker-templates", nil)
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{})
	rec := httptest.NewRecorder()
	h.List(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"template_id"`) {
		t.Fatalf("expected catalog, got %d %s", rec.Code, rec.Body.String())
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd api && go test ./internal/handlers/ -run TestTemplates -v`
Expected: FAIL — undefined `handlers.NewTemplates`.

- [ ] **Step 3: Write minimal implementation**

```go
// api/internal/handlers/templates.go
package handlers

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

// Templates serves the read-only, embedded tracker-template catalog.
type Templates struct{}

func NewTemplates() *Templates { return &Templates{} }

func (h *Templates) List(w http.ResponseWriter, r *http.Request) {
	httpx.WriteJSON(w, http.StatusOK, domain.Templates())
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd api && go test ./internal/handlers/ -run TestTemplates -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add api/internal/handlers/templates.go api/internal/handlers/templates_test.go
git commit -m "feat: tracker-templates handler"
```

---

### Task D5: Wire routes + extend isolation suite

**Files:**

- Modify: `api/cmd/lambda/mux.go`
- Modify: `api/internal/handlers/isolation_test.go`

- [ ] **Step 1: Add env table names in `newStores`**

In `mux.go`, extend the `store.TableNames` literal and the guard:

```go
	names := store.TableNames{
		Users:       os.Getenv("USERS_TABLE"),
		CareGroups:  os.Getenv("CARE_GROUPS_TABLE"),
		Memberships: os.Getenv("MEMBERSHIPS_TABLE"),
		Invitations: os.Getenv("INVITATIONS_TABLE"),
		Receivers:   os.Getenv("RECEIVERS_TABLE"),
		Trackers:    os.Getenv("TRACKERS_TABLE"),
		Events:      os.Getenv("EVENTS_TABLE"),
	}
	if names.Users == "" || names.CareGroups == "" || names.Memberships == "" || names.Invitations == "" ||
		names.Receivers == "" || names.Trackers == "" || names.Events == "" {
		return nil, fmt.Errorf("all DynamoDB table env vars must be set")
	}
```

- [ ] **Step 2: Construct handlers and register routes in `newMux`**

After the existing `inv := handlers.NewInvitations(stores)` line, add:

```go
	rcv := handlers.NewReceivers(stores)
	trk := handlers.NewTrackers(stores)
	evt := handlers.NewEvents(stores)
	tpl := handlers.NewTemplates()
```

After the existing `mux.Handle("POST /invitations/{token}/accept", ...)` line, add:

```go
	mux.Handle("GET /receivers", authn.Wrap(http.HandlerFunc(rcv.List)))
	mux.Handle("POST /care-groups/{careGroupId}/receivers", authn.Wrap(http.HandlerFunc(rcv.Create)))
	mux.Handle("GET /receivers/{receiverId}", authn.Wrap(http.HandlerFunc(rcv.Get)))
	mux.Handle("PATCH /receivers/{receiverId}", authn.Wrap(http.HandlerFunc(rcv.Update)))
	mux.Handle("DELETE /receivers/{receiverId}", authn.Wrap(http.HandlerFunc(rcv.Archive)))

	mux.Handle("GET /receivers/{receiverId}/trackers", authn.Wrap(http.HandlerFunc(trk.ListByReceiver)))
	mux.Handle("POST /receivers/{receiverId}/trackers", authn.Wrap(http.HandlerFunc(trk.Create)))
	mux.Handle("GET /trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Get)))
	mux.Handle("PATCH /trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Update)))
	mux.Handle("DELETE /trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Archive)))

	mux.Handle("GET /trackers/{trackerId}/events", authn.Wrap(http.HandlerFunc(evt.List)))
	mux.Handle("POST /trackers/{trackerId}/events", authn.Wrap(http.HandlerFunc(evt.Create)))
	mux.Handle("GET /trackers/{trackerId}/events/{eventId}", authn.Wrap(http.HandlerFunc(evt.Get)))
	mux.Handle("PATCH /trackers/{trackerId}/events/{eventId}", authn.Wrap(http.HandlerFunc(evt.Update)))
	mux.Handle("DELETE /trackers/{trackerId}/events/{eventId}", authn.Wrap(http.HandlerFunc(evt.Delete)))

	mux.Handle("GET /tracker-templates", authn.Wrap(http.HandlerFunc(tpl.List)))
```

- [ ] **Step 3: Verify the api builds**

Run: `cd api && go build ./...`
Expected: builds clean.

- [ ] **Step 4: Add isolation tests** — append to `api/internal/handlers/isolation_test.go`:

```go
func TestIsolation_nonMemberCannotReadReceiver(t *testing.T) {
	s := dynamotest.Start(t)
	_ = s.Receivers.Put(context.Background(), domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewReceivers(s)
	req := httptest.NewRequest(http.MethodGet, "/receivers/r1", nil)
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Get(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member receiver read should be 403, got %d", rec.Code)
	}
}

func TestIsolation_nonMemberCannotLogEvent(t *testing.T) {
	s := dynamotest.Start(t)
	seedTracker(t, s.Trackers) // tr1 in g1
	h := handlers.NewEvents(s)
	req := httptest.NewRequest(http.MethodPost, "/trackers/tr1/events", strings.NewReader(`{"values":{"systolic":120}}`))
	req.SetPathValue("trackerId", "tr1")
	req = withAuth(req, "stranger", "s@x.com", map[string]domain.Role{"g2": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-member event log should be 403, got %d", rec.Code)
	}
}

func TestIsolation_caregiverCannotCreateTracker(t *testing.T) {
	s := dynamotest.Start(t)
	_ = s.Receivers.Put(context.Background(), domain.Receiver{ReceiverID: "r1", CareGroupID: "g1", Name: "Mom", CreatedAt: time.Now().UTC()})
	h := handlers.NewTrackers(s)
	req := httptest.NewRequest(http.MethodPost, "/receivers/r1/trackers",
		strings.NewReader(`{"name":"W","kind":"measurement","fields":[{"key":"w","label":"W","type":"number"}]}`))
	req.SetPathValue("receiverId", "r1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"g1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("caregiver tracker create should be 403, got %d", rec.Code)
	}
}
```

Note: `seedTracker` is defined in `events_test.go` (same `handlers_test` package), so it is reused here.

- [ ] **Step 5: Run the whole api suite + format**

Run: `cd api && gofmt -w ./... && go test ./...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add api/cmd/lambda/mux.go api/internal/handlers/isolation_test.go
git commit -m "feat: wire b3a routes and extend isolation suite"
```

---

## Section E — Infrastructure (CDK)

**Files in this section:**

- Modify: `infra/lib/shared-stack.ts` — 3 new tables + GSIs, extend `tables` type
- Modify: `infra/lib/api-stack.ts` — props type, env wiring, grants, authed routes
- Modify: `infra/test/api-stack.test.ts` — route count + new route assertions
- Modify: `infra/test/shared-stack.test.ts` — assert the new tables (match existing style)

**Section gate (acceptance criteria):**

- `shared-stack` creates `caregiver-{stage}-{receiver,tracker,event}` with the documented GSIs and exposes them on `this.tables`.
- `api-stack` grants RW + sets `RECEIVERS_TABLE`/`TRACKERS_TABLE`/`EVENTS_TABLE` and registers the 16 authed routes.
- `infra/test` route-count assertion updated to the new total (24) and passes.
- `cd infra && pnpm test` and `pnpm exec cdk synth --context stage=dev` succeed.

---

### Task E1: Tables in shared-stack

**Files:**

- Modify: `infra/lib/shared-stack.ts`

- [ ] **Step 1: Extend the `tables` field type** (in the class field declaration):

```ts
  public readonly tables: {
    users: dynamodb.Table;
    careGroups: dynamodb.Table;
    memberships: dynamodb.Table;
    invitations: dynamodb.Table;
    receivers: dynamodb.Table;
    trackers: dynamodb.Table;
    events: dynamodb.Table;
  };
```

- [ ] **Step 2: Add the three tables** right before the `this.tables = { ... }` assignment:

```ts
const receivers = new dynamodb.Table(this, 'ReceiversTable', {
  ...tableBase,
  tableName: `caregiver-${props.stage}-receiver`,
  partitionKey: { name: 'receiver_id', type: s },
});
receivers.addGlobalSecondaryIndex({
  indexName: 'group-index',
  partitionKey: { name: 'care_group_id', type: s },
  sortKey: { name: 'created_at', type: s },
});

const trackers = new dynamodb.Table(this, 'TrackersTable', {
  ...tableBase,
  tableName: `caregiver-${props.stage}-tracker`,
  partitionKey: { name: 'tracker_id', type: s },
});
trackers.addGlobalSecondaryIndex({
  indexName: 'receiver-index',
  partitionKey: { name: 'receiver_id', type: s },
  sortKey: { name: 'created_at', type: s },
});

const events = new dynamodb.Table(this, 'EventsTable', {
  ...tableBase,
  tableName: `caregiver-${props.stage}-event`,
  partitionKey: { name: 'tracker_id', type: s },
  sortKey: { name: 'event_id', type: s },
});
events.addGlobalSecondaryIndex({
  indexName: 'time-index',
  partitionKey: { name: 'tracker_id', type: s },
  sortKey: { name: 'occurred_at', type: s },
});
```

- [ ] **Step 3: Update the `this.tables` assignment**

```ts
this.tables = { users, careGroups, memberships, invitations, receivers, trackers, events };
```

- [ ] **Step 4: Verify synth compiles**

Run: `cd infra && pnpm exec cdk synth --context stage=dev >/dev/null && echo OK`
Expected: prints `OK` (and rebuilds the Go binary at synth time — Docker not needed for synth, but Go toolchain is).

- [ ] **Step 5: Commit**

```bash
git add infra/lib/shared-stack.ts
git commit -m "feat: receiver/tracker/event dynamodb tables"
```

---

### Task E2: Wire api-stack + update tests

**Files:**

- Modify: `infra/lib/api-stack.ts`
- Modify: `infra/test/api-stack.test.ts`

- [ ] **Step 1: Extend the props `tables` type** in `ApiStackProps`:

```ts
tables: {
  users: dynamodb.ITable;
  careGroups: dynamodb.ITable;
  memberships: dynamodb.ITable;
  invitations: dynamodb.ITable;
  receivers: dynamodb.ITable;
  trackers: dynamodb.ITable;
  events: dynamodb.ITable;
}
```

- [ ] **Step 2: Add env wiring** after the existing `INVITATIONS_TABLE` line (the `for...grantReadWriteData` loop already covers the new tables via `Object.values(props.tables)`):

```ts
this.apiFunction.addEnvironment('RECEIVERS_TABLE', props.tables.receivers.tableName);
this.apiFunction.addEnvironment('TRACKERS_TABLE', props.tables.trackers.tableName);
this.apiFunction.addEnvironment('EVENTS_TABLE', props.tables.events.tableName);
```

- [ ] **Step 3: Add the 16 routes** to the `authedRoutes` array:

```ts
      { path: '/receivers', methods: [apigw.HttpMethod.GET] },
      { path: '/care-groups/{careGroupId}/receivers', methods: [apigw.HttpMethod.POST] },
      { path: '/receivers/{receiverId}', methods: [apigw.HttpMethod.GET] },
      { path: '/receivers/{receiverId}', methods: [apigw.HttpMethod.PATCH] },
      { path: '/receivers/{receiverId}', methods: [apigw.HttpMethod.DELETE] },
      { path: '/receivers/{receiverId}/trackers', methods: [apigw.HttpMethod.GET] },
      { path: '/receivers/{receiverId}/trackers', methods: [apigw.HttpMethod.POST] },
      { path: '/trackers/{trackerId}', methods: [apigw.HttpMethod.GET] },
      { path: '/trackers/{trackerId}', methods: [apigw.HttpMethod.PATCH] },
      { path: '/trackers/{trackerId}', methods: [apigw.HttpMethod.DELETE] },
      { path: '/trackers/{trackerId}/events', methods: [apigw.HttpMethod.GET] },
      { path: '/trackers/{trackerId}/events', methods: [apigw.HttpMethod.POST] },
      { path: '/trackers/{trackerId}/events/{eventId}', methods: [apigw.HttpMethod.GET] },
      { path: '/trackers/{trackerId}/events/{eventId}', methods: [apigw.HttpMethod.PATCH] },
      { path: '/trackers/{trackerId}/events/{eventId}', methods: [apigw.HttpMethod.DELETE] },
      { path: '/tracker-templates', methods: [apigw.HttpMethod.GET] },
```

- [ ] **Step 4: Update the route-count test** in `infra/test/api-stack.test.ts`

The previous total was 8 (2 public + 6 authed). B3a adds 16 authed routes → **24**. Change:

```ts
t.resourceCountIs('AWS::ApiGatewayV2::Route', 24);
```

And add a few new route-key assertions alongside the existing loop (e.g. extend the authed `for` array with `'GET /receivers'`, `'POST /trackers/{trackerId}/events'`, `'GET /tracker-templates'`).

- [ ] **Step 5: Run infra tests + synth**

Run: `cd infra && pnpm test && pnpm exec cdk synth --context stage=dev >/dev/null && echo OK`
Expected: tests pass; prints `OK`.

- [ ] **Step 6: Commit**

```bash
git add infra/lib/api-stack.ts infra/test/api-stack.test.ts
git commit -m "feat: grant and route b3a endpoints in api stack"
```

---

## Section F — Docs, full verification & PR

**Files in this section:**

- Modify: `CLAUDE.md` — B3a status + table list
- Modify: `docs/roadmap.md` — mark B3a done / B3 decomposed
- Modify: `docs/TECH_DEBT.md` — note partial store-helper retrofit if applicable

**Section gate (acceptance criteria):**

- All suites green: `shared/go-common`, `api`, `infra`.
- Codegen-drift check passes (regenerated files committed).
- Docs updated; PR opened (not merged).

---

### Task F1: Full verification

- [ ] **Step 1: Run every test suite**

Run:

```bash
cd shared/go-common && go test ./... && \
cd ../../api && go test ./... && \
cd ../infra && pnpm test
```

Expected: all PASS (Docker running for the Go suites).

- [ ] **Step 2: Confirm no codegen drift**

Run: `cd shared/types-go && make codegen` then `git status --porcelain`
Expected: no unexpected diffs (regenerated files already committed in Task C1).

- [ ] **Step 3: Lint Go + format everything**

Run: `cd shared/go-common && go vet ./... && cd ../api && go vet ./...`
Expected: clean.

---

### Task F2: Update docs

**Files:**

- Modify: `CLAUDE.md`, `docs/roadmap.md`, `docs/TECH_DEBT.md`

- [ ] **Step 1: Update `CLAUDE.md`** — change the status line to note B3a done (Receivers/Trackers/Events) and add the three new tables to the "B1 domain model" table region (or a new B3a note). Keep it concise and consistent with the existing prose.

- [ ] **Step 2: Update `docs/roadmap.md`** — mark B3 as decomposed; B3a done; B3b (Schedules/NotifPrefs/Audit) still planned.

- [ ] **Step 3: Update `docs/TECH_DEBT.md`** — if the four B1 stores were not retrofitted onto the new generic helpers, record that as a deferred follow-up; otherwise remove the corresponding B1 note.

- [ ] **Step 4: Format docs + commit**

```bash
pnpm exec prettier --write CLAUDE.md docs/roadmap.md docs/TECH_DEBT.md
git add CLAUDE.md docs/roadmap.md docs/TECH_DEBT.md
git commit -m "docs: b3a status, tables, and tech-debt update"
```

---

### Task F3: Open the PR (do NOT merge)

- [ ] **Step 1: Push the branch**

Run: `git push -u origin b3a-core-care-domain`

- [ ] **Step 2: Open the PR**

Run:

```bash
gh pr create --base main --title "feat: B3a core care domain (receivers, trackers, events)" --body "$(cat <<'EOF'
Implements B3a per docs/specs/2026-06-12-b3a-core-care-domain-design.md and
docs/plans/2026-06-12-b3a-core-care-domain.md.

- Receivers, Trackers (custom field schema + thresholds), Events (validated,
  paginated history, computed breach flag), and the embedded tracker-template
  catalog.
- Reuses the B1 auth seam unchanged; isolation suite extended to every new route.
- 3 new DynamoDB tables wired through CDK.

Schedules / NotificationPreferences / Audit and member management are deferred
to later B3 slices.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Stop.** Do not merge. Ask Trevor to review — merging to `main` triggers a prod deploy via `cd-main`.

---

## Self-review notes (for the implementer)

- **Spec coverage:** Receivers (Tasks B3, D1, E1), Trackers + full field schema (A1, B4, D2), Events + validation + breach + pagination (A2, B5, D3), templates (A3, D4), denormalized `care_group_id` (A1 types; D2/D3 set it; B-stores carry it), soft-archive (B3/B4 + handler 404-on-archived), permissions (D1–D3 authz), isolation (D5), contract + codegen (C1), infra (E1/E2), forward constraints unchanged.
- **`occurred_at` format:** stored by the attributevalue marshaler as RFC3339Nano; the event store's range filter formats `from`/`to` identically (B5). Keep this in sync if the event time field ever changes type.
- **`map[string]any` numbers:** JSON decodes numbers to `float64`; `ValidateValues` and `Breaches` rely on this. DynamoDB round-trips numeric `values` back to `float64` via `attributevalue` into `map[string]any`, so list/get breach computation matches create.
- **Cursor assumption:** `EncodeCursor`/`DecodeCursor` only handle string-typed key attributes (true for `tracker_id`/`event_id`/`occurred_at`). If a future index adds a numeric key, extend the cursor codec.
