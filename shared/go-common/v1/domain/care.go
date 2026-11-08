package domain

import "time"

type ReceiverStatus string

const (
	ReceiverActive   ReceiverStatus = "active"
	ReceiverArchived ReceiverStatus = "archived"
)

// Receiver is a care receiver on a team. TimeZone is the IANA zone every
// wall-clock time about the receiver is read in.
type Receiver struct {
	ReceiverID string         `dynamodbav:"receiver_id"`
	TeamID     string         `dynamodbav:"team_id"`
	Name       string         `dynamodbav:"name"`
	TimeZone   string         `dynamodbav:"time_zone"`
	Status     ReceiverStatus `dynamodbav:"status"`
	ArchivedBy string         `dynamodbav:"archived_by,omitempty"`
	ArchivedAt *time.Time     `dynamodbav:"archived_at,omitempty"`
	CreatedBy  string         `dynamodbav:"created_by"`
	CreatedAt  time.Time      `dynamodbav:"created_at"`
}

type TrackerStatus string

const (
	TrackerActive TrackerStatus = "active"
	TrackerPaused TrackerStatus = "paused"
)

func (s TrackerStatus) Valid() bool { return s == TrackerActive || s == TrackerPaused }

type FieldType string

const (
	FieldNumber   FieldType = "number"
	FieldText     FieldType = "text"
	FieldBoolean  FieldType = "boolean"
	FieldChoice   FieldType = "choice"
	FieldDatetime FieldType = "datetime"
)

func (t FieldType) Valid() bool {
	switch t {
	case FieldNumber, FieldText, FieldBoolean, FieldChoice, FieldDatetime:
		return true
	}
	return false
}

type FieldStatus string

const (
	FieldActive FieldStatus = "active"
	FieldPaused FieldStatus = "paused"
)

func (s FieldStatus) Valid() bool { return s == FieldActive || s == FieldPaused }

type OptionStatus string

const (
	OptionActive  OptionStatus = "active"
	OptionRetired OptionStatus = "retired"
)

func (s OptionStatus) Valid() bool { return s == OptionActive || s == OptionRetired }

// Range is where a number field is expected to stay. Either bound may be open;
// pointers tell an open bound from a real zero.
type Range struct {
	Low  *float64 `dynamodbav:"low,omitempty"`
	High *float64 `dynamodbav:"high,omitempty"`
}

// Contains reports whether v is within the range, bounds inclusive.
func (r Range) Contains(v float64) bool {
	return (r.Low == nil || v >= *r.Low) && (r.High == nil || v <= *r.High)
}

// ChoiceOption is one answer a choice field offers. Entries store OptionID, so a
// rename reads everywhere and a retirement leaves old entries intact.
type ChoiceOption struct {
	OptionID string       `dynamodbav:"option_id"`
	Label    string       `dynamodbav:"label"`
	Status   OptionStatus `dynamodbav:"status"`
}

// Field is embedded in its tracker and never removed from the list. Range is
// number only; Multiple and Options are choice only.
type Field struct {
	FieldID  string         `dynamodbav:"field_id"`
	Label    string         `dynamodbav:"label"`
	Type     FieldType      `dynamodbav:"type"`
	Unit     string         `dynamodbav:"unit,omitempty"`
	Required bool           `dynamodbav:"required"`
	Status   FieldStatus    `dynamodbav:"status"`
	PausedAt *time.Time     `dynamodbav:"paused_at,omitempty"`
	Range    *Range         `dynamodbav:"range,omitempty"`
	Multiple bool           `dynamodbav:"multiple,omitempty"`
	Options  []ChoiceOption `dynamodbav:"options,omitempty"`
}

// Tracker belongs to one receiver; team_id is denormalized from it. GapHours is
// nil when no gap watches it. Migrated rows may lack Icon and Color.
type Tracker struct {
	TrackerID  string        `dynamodbav:"tracker_id"`
	ReceiverID string        `dynamodbav:"receiver_id"`
	TeamID     string        `dynamodbav:"team_id"`
	Name       string        `dynamodbav:"name"`
	Icon       string        `dynamodbav:"icon,omitempty"`
	Color      string        `dynamodbav:"color,omitempty"`
	Fields     []Field       `dynamodbav:"fields"`
	GapHours   *int          `dynamodbav:"gap_hours,omitempty"`
	Status     TrackerStatus `dynamodbav:"status"`
	PausedBy   string        `dynamodbav:"paused_by,omitempty"`
	PausedAt   *time.Time    `dynamodbav:"paused_at,omitempty"`
	CreatedBy  string        `dynamodbav:"created_by"`
	CreatedAt  time.Time     `dynamodbav:"created_at"`
}

// Rule is a recurrence rule, never a preset: an RRULE subset that can widen
// without migrating data.
type Rule struct {
	Freq     string   `dynamodbav:"freq"`
	Interval int      `dynamodbav:"interval"`
	ByDay    []string `dynamodbav:"by_day,omitempty"`
}

// Schedule is a tracker's recurring plan. Time is local HH:MM and StartsOn/EndsOn
// local YYYY-MM-DD dates, all in the receiver's zone. A removed schedule keeps
// its row (RemovedAt set) so past entries can still name it. GeneratedThrough is
// the generator's bookmark; its format is the generator's to fix.
type Schedule struct {
	ScheduleID       string         `dynamodbav:"schedule_id"`
	TrackerID        string         `dynamodbav:"tracker_id"`
	ReceiverID       string         `dynamodbav:"receiver_id"`
	TeamID           string         `dynamodbav:"team_id"`
	Label            string         `dynamodbav:"label,omitempty"`
	Rule             Rule           `dynamodbav:"rule"`
	Time             string         `dynamodbav:"time"`
	StartsOn         string         `dynamodbav:"starts_on"`
	EndsOn           string         `dynamodbav:"ends_on,omitempty"`
	PlannedValues    map[string]any `dynamodbav:"planned_values"`
	UnrecordedAlert  bool           `dynamodbav:"unrecorded_alert"`
	GraceMinutes     *int           `dynamodbav:"grace_minutes,omitempty"`
	RemovedAt        *time.Time     `dynamodbav:"removed_at,omitempty"`
	GeneratedThrough string         `dynamodbav:"generated_through,omitempty"`
	CreatedBy        string         `dynamodbav:"created_by"`
	CreatedAt        time.Time      `dynamodbav:"created_at"`
}

// EntryState is what an entry is. Only scheduled, logged and skipped are stored;
// EntryUnrecorded is derived by DisplayState and never written.
type EntryState string

const (
	EntryScheduled  EntryState = "scheduled"
	EntryLogged     EntryState = "logged"
	EntrySkipped    EntryState = "skipped"
	EntryUnrecorded EntryState = "unrecorded"
)

// Entry is one record for all four states. The plan fields (OccurrenceAt and
// the rest) are present when it was planned; ScheduleID is absent for one made
// by hand. Values are keyed by field_id; a choice is a list of option_ids.
// TimelineAt is OccurredAt if logged, otherwise OccurrenceAt. OpenAt is set
// only while scheduled, so the sparse open-index holds only care still waiting.
// Index keys are omitempty: DynamoDB rejects an empty string as a GSI key.
type Entry struct {
	EntryID    string `dynamodbav:"entry_id"`
	TrackerID  string `dynamodbav:"tracker_id"`
	ReceiverID string `dynamodbav:"receiver_id"`
	TeamID     string `dynamodbav:"team_id"`

	ScheduleID      string         `dynamodbav:"schedule_id,omitempty"`
	OccurrenceLocal string         `dynamodbav:"occurrence_local,omitempty"` // YYYY-MM-DDTHH:MM in the receiver's zone
	OccurrenceAt    *time.Time     `dynamodbav:"occurrence_at,omitempty"`
	PlannedValues   map[string]any `dynamodbav:"planned_values,omitempty"`
	UnrecordedAlert bool           `dynamodbav:"unrecorded_alert,omitempty"`
	GraceMinutes    *int           `dynamodbav:"grace_minutes,omitempty"`

	State      EntryState     `dynamodbav:"state"`
	Values     map[string]any `dynamodbav:"values"`
	Note       string         `dynamodbav:"note,omitempty"`
	OccurredAt *time.Time     `dynamodbav:"occurred_at,omitempty"`
	LoggedBy   string         `dynamodbav:"logged_by,omitempty"`
	LoggedAt   *time.Time     `dynamodbav:"logged_at,omitempty"`
	SkippedBy  string         `dynamodbav:"skipped_by,omitempty"`
	SkippedAt  *time.Time     `dynamodbav:"skipped_at,omitempty"`

	CreatedBy string     `dynamodbav:"created_by"`
	CreatedAt time.Time  `dynamodbav:"created_at"`
	UpdatedBy string     `dynamodbav:"updated_by,omitempty"`
	UpdatedAt *time.Time `dynamodbav:"updated_at,omitempty"`

	TimelineAt time.Time  `dynamodbav:"timeline_at"`
	OpenAt     *time.Time `dynamodbav:"open_at,omitempty"`
}

// DisplayState is the state a caregiver sees: a scheduled entry whose
// occurrence time is at or before now reads as unrecorded.
func (e Entry) DisplayState(now time.Time) EntryState {
	if e.State == EntryScheduled && e.OccurrenceAt != nil && !e.OccurrenceAt.After(now) {
		return EntryUnrecorded
	}
	return e.State
}
