package store_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestMarshalItem_fixedWidthUTC(t *testing.T) {
	at := time.Date(2026, 11, 8, 6, 0, 0, 500_000_000, time.FixedZone("CST", -6*3600))
	item, err := store.MarshalItem(loggedEntry("e", "tr1", at, nil))
	if err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"timeline_at", "occurred_at", "created_at"} {
		if got := item[k].(*types.AttributeValueMemberS).Value; got != "2026-11-08T12:00:00.500000000Z" {
			t.Fatalf("%s = %q", k, got)
		}
	}
}

// A whole second and the half second after it sort in time order, and a row
// written in the old variable-width form still reads and still bounds.
func TestTimeFormat_sortsAndReadsOld(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	whole := now.Add(-time.Hour)
	seed(t, l, l.Names.Entries, loggedEntry("half", "tr1", whole.Add(500*time.Millisecond), nil))
	seed(t, l, l.Names.Entries, loggedEntry("whole", "tr1", whole, nil))
	seed(t, l, l.Names.Entries, map[string]any{
		"entry_id": "old", "tracker_id": "tr1", "receiver_id": "r1", "team_id": "t1", "state": "logged",
		"values": map[string]any{}, "occurred_at": "2026-11-08T10:00:00.25Z", "created_by": "u1",
		"created_at": "2026-11-08T10:00:00.25Z", "timeline_at": "2026-11-08T10:00:00.250000000Z",
	})

	got, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", whole.Add(500*time.Millisecond), nil, 10, "")
	var ids []string
	for _, e := range got {
		ids = append(ids, e.EntryID)
	}
	if err != nil || fmt.Sprint(ids) != "[half whole old]" {
		t.Fatalf("got %v err=%v", ids, err)
	}
	if !got[2].OccurredAt.Equal(time.Date(2026, 11, 8, 10, 0, 0, 250_000_000, time.UTC)) {
		t.Fatalf("old occurred_at: %v", got[2].OccurredAt)
	}
	// An inclusive bound on exactly the whole second keeps it.
	got, _, _ = l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", whole, &whole, 10, "")
	if len(got) != 1 || got[0].EntryID != "whole" {
		t.Fatalf("inclusive bound: %+v", got)
	}
}

func TestEntry_cursorFromAnotherTrackerIsInvalid(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	for i := 0; i < 3; i++ {
		seed(t, l, l.Names.Entries, loggedEntry(fmt.Sprintf("a%d", i), "tr1", now.Add(-time.Duration(i+1)*time.Hour), nil))
	}
	_, cursor, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr1", now, nil, 1, "")
	if err != nil || cursor == "" {
		t.Fatalf("first page: cursor=%q err=%v", cursor, err)
	}
	if _, _, err := l.Stores.Entries.ListByTrackerTimeline(ctx, "tr2", now, nil, 1, cursor); err != store.ErrInvalidCursor {
		t.Fatalf("want ErrInvalidCursor, got %v", err)
	}
}
