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
	Options   []string   `dynamodbav:"options,omitempty" json:"options,omitempty"`     // required iff type==enum
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
