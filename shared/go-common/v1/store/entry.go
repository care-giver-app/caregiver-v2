package store

import (
	"context"
	"errors"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// RecentLoggedLimit is how many logged entries back RecentLoggedByTracker is
// asked to read for a tracker's last_logged_at and its latest reading per
// ranged field. A ranged field last recorded further back than this is not
// seen; at family scale (a few entries a day per tracker) that is weeks.
const RecentLoggedLimit = 100

type EntryStore struct {
	client *dynamodb.Client
	table  string
}

// The tracker-time index's LastEvaluatedKey: the table key plus the index key.
var trackerTimeCursorKeys = []string{"entry_id", "tracker_id", "timeline_at"}

// ListByTrackerTimeline returns one page of the tracker's entries, newest first
// by timeline_at, with timeline_at <= to and, when from is set, >= from. Every
// stored state is included. The cursor is the one the previous page returned
// ("" for the first); the returned cursor is "" on the last page. A cursor not
// issued by this method returns ErrInvalidCursor.
func (s *EntryStore) ListByTrackerTimeline(ctx context.Context, trackerID string, to time.Time, from *time.Time, limit int32, cursor string) ([]domain.Entry, string, error) {
	start, err := decodeCursor(cursor, trackerTimeCursorKeys...)
	if err != nil {
		return nil, "", err
	}
	keyCond := "tracker_id = :t AND timeline_at <= :to"
	vals := map[string]types.AttributeValue{
		":t":  &types.AttributeValueMemberS{Value: trackerID},
		":to": timeKey(to),
	}
	if from != nil {
		keyCond = "tracker_id = :t AND timeline_at BETWEEN :from AND :to"
		vals[":from"] = timeKey(*from)
	}
	in := &dynamodb.QueryInput{
		TableName:                 aws.String(s.table),
		IndexName:                 aws.String(trackerTime),
		KeyConditionExpression:    aws.String(keyCond),
		ExpressionAttributeValues: vals,
		ScanIndexForward:          aws.Bool(false),
		ExclusiveStartKey:         start,
	}
	if limit > 0 {
		in.Limit = aws.Int32(limit)
	}
	out, err := s.client.Query(ctx, in)
	if err != nil {
		return nil, "", err
	}
	var entries []domain.Entry
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &entries); err != nil {
		return nil, "", err
	}
	next, err := encodeCursor(out.LastEvaluatedKey)
	if err != nil {
		return nil, "", err
	}
	return entries, next, nil
}

// RecentLoggedByTracker returns up to n of the tracker's logged entries, newest
// first by timeline_at (occurred_at for a logged entry). It pages back through
// the tracker-time index, skipping other states, until it has n or runs out.
// Callers pass RecentLoggedLimit.
func (s *EntryStore) RecentLoggedByTracker(ctx context.Context, trackerID string, n int) ([]domain.Entry, error) {
	if n <= 0 {
		return nil, nil
	}
	in := &dynamodb.QueryInput{
		TableName:                aws.String(s.table),
		IndexName:                aws.String(trackerTime),
		KeyConditionExpression:   aws.String("tracker_id = :t"),
		FilterExpression:         aws.String("#s = :logged"),
		ExpressionAttributeNames: map[string]string{"#s": "state"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t":      &types.AttributeValueMemberS{Value: trackerID},
			":logged": &types.AttributeValueMemberS{Value: string(domain.EntryLogged)},
		},
		ScanIndexForward: aws.Bool(false),
		Limit:            aws.Int32(int32(n)),
	}
	var entries []domain.Entry
	for {
		out, err := s.client.Query(ctx, in)
		if err != nil {
			return nil, err
		}
		var page []domain.Entry
		if err := attributevalue.UnmarshalListOfMaps(out.Items, &page); err != nil {
			return nil, err
		}
		entries = append(entries, page...)
		if len(entries) >= n {
			return entries[:n], nil
		}
		if len(out.LastEvaluatedKey) == 0 {
			return entries, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}

// OpenByReceiver returns the receiver's scheduled (still open) entries with
// open_at in [from, to], oldest first, via the sparse open-index. A non-empty
// trackerID keeps only that tracker's.
func (s *EntryStore) OpenByReceiver(ctx context.Context, receiverID, trackerID string, from, to time.Time) ([]domain.Entry, error) {
	in := &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(openIndex),
		KeyConditionExpression: aws.String("receiver_id = :r AND open_at BETWEEN :from AND :to"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r":    &types.AttributeValueMemberS{Value: receiverID},
			":from": timeKey(from),
			":to":   timeKey(to),
		},
		ScanIndexForward: aws.Bool(true),
	}
	if trackerID != "" {
		in.FilterExpression = aws.String("tracker_id = :t")
		in.ExpressionAttributeValues[":t"] = &types.AttributeValueMemberS{Value: trackerID}
	}
	return queryAll[domain.Entry](ctx, s.client, in)
}

// DeleteFutureOpenForTracker deletes the tracker's scheduled entries whose
// open_at is after now — the occurrences still to come, which pausing removes.
// Logged, skipped and already-unrecorded entries stay. Each delete is
// conditional on the entry still being scheduled, so one logged meanwhile
// survives. It returns how many were deleted.
func (s *EntryStore) DeleteFutureOpenForTracker(ctx context.Context, trackerID string, now time.Time) (int, error) {
	in := &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(trackerTime),
		KeyConditionExpression: aws.String("tracker_id = :t AND timeline_at > :now"),
		FilterExpression:       aws.String("open_at > :now"),
		ProjectionExpression:   aws.String("entry_id"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t":   &types.AttributeValueMemberS{Value: trackerID},
			":now": timeKey(now),
		},
	}
	deleted := 0
	for {
		out, err := s.client.Query(ctx, in)
		if err != nil {
			return deleted, err
		}
		for _, item := range out.Items {
			_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
				TableName:                aws.String(s.table),
				Key:                      map[string]types.AttributeValue{"entry_id": item["entry_id"]},
				ConditionExpression:      aws.String("#s = :scheduled"),
				ExpressionAttributeNames: map[string]string{"#s": "state"},
				ExpressionAttributeValues: map[string]types.AttributeValue{
					":scheduled": &types.AttributeValueMemberS{Value: string(domain.EntryScheduled)},
				},
			})
			var ccf *types.ConditionalCheckFailedException
			switch {
			case err == nil:
				deleted++
			case errors.As(err, &ccf):
			default:
				return deleted, err
			}
		}
		if len(out.LastEvaluatedKey) == 0 {
			return deleted, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}
