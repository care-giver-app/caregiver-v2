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
