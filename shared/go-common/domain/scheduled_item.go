package domain

import "time"

// ScheduledItem is a discrete, dated, planned entry on a scheduled-kind tracker.
// It is a near-twin of Event: the same denormalized ids and values map (validated
// against the tracker's fields via ValidateValues), but future-facing
// (scheduled_for) rather than past (occurred_at). See api/specs/scheduled-items.md.
type ScheduledItem struct {
	ScheduledItemID string         `dynamodbav:"scheduled_item_id" json:"scheduled_item_id"`
	TrackerID       string         `dynamodbav:"tracker_id" json:"tracker_id"`
	CareGroupID     string         `dynamodbav:"care_group_id" json:"care_group_id"`
	ReceiverID      string         `dynamodbav:"receiver_id" json:"receiver_id"`
	Values          map[string]any `dynamodbav:"values" json:"values"`
	Note            string         `dynamodbav:"note,omitempty" json:"note,omitempty"`
	ScheduledFor    time.Time      `dynamodbav:"scheduled_for" json:"scheduled_for"`
	CreatedBy       string         `dynamodbav:"created_by" json:"created_by"`
	CreatedAt       time.Time      `dynamodbav:"created_at" json:"created_at"`
}
