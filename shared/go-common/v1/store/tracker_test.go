package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func f64(v float64) *float64 { return &v }

func bpTracker(id string, created time.Time) domain.Tracker {
	gap := 72
	return domain.Tracker{
		TrackerID: id, ReceiverID: "r1", TeamID: "t1", Name: "Blood pressure", Icon: "heart", Color: "#E5484D",
		Fields: []domain.Field{
			{FieldID: "sys", Label: "Systolic", Type: domain.FieldNumber, Unit: "mmHg", Required: true, Status: domain.FieldActive,
				Range: &domain.Range{Low: f64(0), High: f64(140)}},
			{FieldID: "mood", Label: "Mood", Type: domain.FieldChoice, Status: domain.FieldActive, Multiple: true,
				Options: []domain.ChoiceOption{{OptionID: "o1", Label: "Good", Status: domain.OptionActive}}},
		},
		GapHours: &gap, Status: domain.TrackerActive, CreatedBy: "u1", CreatedAt: created,
	}
}

func TestTracker_CreateGetPutList(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)

	tr := bpTracker("tr1", now)
	if err := s.Trackers.Create(ctx, tr); err != nil {
		t.Fatalf("create: %v", err)
	}
	var ccf *types.ConditionalCheckFailedException
	if err := s.Trackers.Create(ctx, bpTracker("tr1", now)); !errors.As(err, &ccf) {
		t.Fatalf("duplicate create should fail the condition, got %v", err)
	}
	// A non-UTC created_at is normalized so receiver-index sorts correctly.
	if err := s.Trackers.Create(ctx, bpTracker("tr0", now.Add(-time.Hour).In(time.FixedZone("CST", -6*3600)))); err != nil {
		t.Fatalf("create tr0: %v", err)
	}

	got, err := s.Trackers.Get(ctx, "tr1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Name != "Blood pressure" || got.GapHours == nil || *got.GapHours != 72 || len(got.Fields) != 2 ||
		got.Fields[0].Range == nil || got.Fields[0].Range.Low == nil || *got.Fields[0].Range.Low != 0 ||
		!got.Fields[1].Multiple || got.Fields[1].Options[0].OptionID != "o1" || !got.CreatedAt.Equal(now) {
		t.Fatalf("round trip: %+v", got)
	}
	if _, err := s.Trackers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	got.Name, got.GapHours = "BP", nil
	if err := s.Trackers.Put(ctx, got); err != nil {
		t.Fatalf("put: %v", err)
	}
	if again, _ := s.Trackers.Get(ctx, "tr1"); again.Name != "BP" || again.GapHours != nil {
		t.Fatalf("put not stored: %+v", again)
	}
	if err := s.Trackers.Put(ctx, bpTracker("missing", now)); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("put of a missing tracker: want ErrNotFound, got %v", err)
	}
	if _, err := s.Trackers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("put must not create")
	}
	// A pause landing between Edit's read and its Save survives the Save.
	stale, _ := s.Trackers.Get(ctx, "tr1")
	if _, err := s.Trackers.SetStatus(ctx, "tr1", domain.TrackerPaused, "u2", now); err != nil {
		t.Fatalf("pause: %v", err)
	}
	stale.Name = "BP edited"
	if err := s.Trackers.Put(ctx, stale); err != nil {
		t.Fatalf("stale put: %v", err)
	}
	if after, _ := s.Trackers.Get(ctx, "tr1"); after.Name != "BP edited" || after.Status != domain.TrackerPaused || after.PausedAt == nil {
		t.Fatalf("edit undid the pause: %+v", after)
	}
	if _, err := s.Trackers.SetStatus(ctx, "tr1", domain.TrackerActive, "u2", now); err != nil {
		t.Fatalf("resume: %v", err)
	}

	list, err := s.Trackers.ListByReceiver(ctx, "r1")
	if err != nil || len(list) != 2 || list[0].TrackerID != "tr0" || list[1].TrackerID != "tr1" {
		t.Fatalf("list: %+v err=%v", list, err)
	}
}

func TestTracker_SetStatus(t *testing.T) {
	s := dynamotest.Start(t)
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)
	if err := s.Trackers.Create(ctx, bpTracker("tr1", now)); err != nil {
		t.Fatalf("create: %v", err)
	}

	paused, err := s.Trackers.SetStatus(ctx, "tr1", domain.TrackerPaused, "u1", now)
	if err != nil || paused.Status != domain.TrackerPaused || paused.PausedBy != "u1" || paused.PausedAt == nil ||
		!paused.PausedAt.Equal(now) || paused.Name != "Blood pressure" {
		t.Fatalf("pause: %+v err=%v", paused, err)
	}
	again, err := s.Trackers.SetStatus(ctx, "tr1", domain.TrackerPaused, "u2", now.Add(time.Hour))
	if err != nil || again.PausedBy != "u1" || !again.PausedAt.Equal(now) {
		t.Fatalf("pausing a paused tracker should change nothing: %+v err=%v", again, err)
	}

	resumed, err := s.Trackers.SetStatus(ctx, "tr1", domain.TrackerActive, "u1", now.Add(2*time.Hour))
	if err != nil || resumed.Status != domain.TrackerActive || resumed.PausedBy != "" || resumed.PausedAt != nil {
		t.Fatalf("resume: %+v err=%v", resumed, err)
	}
	if stored, _ := s.Trackers.Get(ctx, "tr1"); stored.PausedAt != nil || stored.Status != domain.TrackerActive {
		t.Fatalf("stored: %+v", stored)
	}
	if r, err := s.Trackers.SetStatus(ctx, "tr1", domain.TrackerActive, "u1", now); err != nil || r.Status != domain.TrackerActive {
		t.Fatalf("resuming an active tracker: %+v err=%v", r, err)
	}

	if _, err := s.Trackers.SetStatus(ctx, "missing", domain.TrackerPaused, "u1", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
	if _, err := s.Trackers.Get(ctx, "missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("SetStatus must not create")
	}
}

// A tracker row exactly as scripts/migrate_to_v1.py writes it: no icon or
// gap, a choice field with multiple=false, a number field with only a low bound.
func TestTracker_readsMigratedRow(t *testing.T) {
	l := dynamotest.StartLocal(t)
	seed(t, l, l.Names.Trackers, map[string]any{
		"tracker_id": "tr1", "receiver_id": "r1", "team_id": "t1", "name": "Meals",
		"fields": []any{
			map[string]any{"field_id": "amount", "label": "Amount", "type": "choice", "required": true, "status": "active",
				"multiple": false, "options": []any{map[string]any{"option_id": "o1", "label": "All", "status": "active"}}},
			map[string]any{"field_id": "weight", "label": "Weight", "type": "number", "required": false, "status": "active",
				"unit": "lb", "range": map[string]any{"low": 100}},
		},
		"status": "active", "created_by": "u1", "created_at": "2026-06-12T14:30:00Z",
	})
	got, err := l.Stores.Trackers.Get(context.Background(), "tr1")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Icon != "" || got.GapHours != nil || got.Status != domain.TrackerActive || len(got.Fields) != 2 {
		t.Fatalf("got %+v", got)
	}
	if c := got.Fields[0]; c.Type != domain.FieldChoice || c.Multiple || len(c.Options) != 1 || c.Options[0].Status != domain.OptionActive {
		t.Fatalf("choice: %+v", c)
	}
	if n := got.Fields[1]; n.Range == nil || n.Range.Low == nil || *n.Range.Low != 100 || n.Range.High != nil || n.Unit != "lb" {
		t.Fatalf("number: %+v", n)
	}
	list, err := l.Stores.Trackers.ListByReceiver(context.Background(), "r1")
	if err != nil || len(list) != 1 {
		t.Fatalf("list: %+v err=%v", list, err)
	}
}
