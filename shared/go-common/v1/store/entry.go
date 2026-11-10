package store

import (
	"context"
	"errors"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/smithy-go"

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
// issued by this method for this tracker and these bounds returns
// ErrInvalidCursor.
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
	var apiErr smithy.APIError
	if start != nil && errors.As(err, &apiErr) && apiErr.ErrorCode() == "ValidationException" {
		// A well-formed cursor from another tracker or outside these bounds.
		return nil, "", ErrInvalidCursor
	}
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

func entryKey(entryID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"entry_id": &types.AttributeValueMemberS{Value: entryID}}
}

// Get returns one entry, in whatever state it is in, or ErrNotFound.
func (s *EntryStore) Get(ctx context.Context, entryID string) (domain.Entry, error) {
	return getItem[domain.Entry](ctx, s.client, s.table, entryKey(entryID))
}

// ListByReceiverBetween returns every entry of the receiver, in every state and
// from every tracker (paused ones included), whose timeline_at is in [from, to),
// oldest first, via the receiver-time index. It reads to the end: the caller
// bounds it to one local day, which family scale keeps small. Leaving out the
// occurrences still to come is the caller's, since that depends on now.
func (s *EntryStore) ListByReceiverBetween(ctx context.Context, receiverID string, from, to time.Time) ([]domain.Entry, error) {
	if !to.After(from) {
		return nil, nil
	}
	return queryAll[domain.Entry](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(receiverTime),
		KeyConditionExpression: aws.String("receiver_id = :r AND timeline_at BETWEEN :from AND :to"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r":    &types.AttributeValueMemberS{Value: receiverID},
			":from": timeKey(from),
			// Stored times carry nanoseconds, so the nanosecond before to is
			// the last one inside a half-open [from, to).
			":to": timeKey(to.Add(-time.Nanosecond)),
		},
		ScanIndexForward: aws.Bool(true),
	})
}

// NextOpenByTracker returns, for each of trackerIDs, its soonest scheduled
// entry whose open_at is after now, soonest first; a tracker with none is
// absent. It walks the receiver's open-index forward from now and stops once
// every tracker asked about has been found, so a tracker with a far-off next
// occurrence (the generator always writes each schedule's next one, however
// far beyond its horizon) costs reading up to it, never past it. Entries of
// trackers not asked about — paused ones, say — are passed over.
func (s *EntryStore) NextOpenByTracker(ctx context.Context, receiverID string, trackerIDs []string, now time.Time) ([]domain.Entry, error) {
	want := make(map[string]bool, len(trackerIDs))
	for _, id := range trackerIDs {
		want[id] = true
	}
	if len(want) == 0 {
		return nil, nil
	}
	in := &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(openIndex),
		KeyConditionExpression: aws.String("receiver_id = :r AND open_at > :now"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r":   &types.AttributeValueMemberS{Value: receiverID},
			":now": timeKey(now),
		},
		ScanIndexForward: aws.Bool(true),
	}
	var next []domain.Entry
	for {
		out, err := s.client.Query(ctx, in)
		if err != nil {
			return nil, err
		}
		var page []domain.Entry
		if err := attributevalue.UnmarshalListOfMaps(out.Items, &page); err != nil {
			return nil, err
		}
		for _, e := range page {
			if want[e.TrackerID] {
				delete(want, e.TrackerID)
				next = append(next, e)
				if len(want) == 0 {
					return next, nil
				}
			}
		}
		if len(out.LastEvaluatedKey) == 0 {
			return next, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}

// OpenByReceiver returns the receiver's scheduled (still open) entries with
// open_at in [from, to], oldest first, via the sparse open-index. A non-empty
// trackerID keeps only that tracker's. Quick log's waiting list is one call:
// from now less UnrecordedWindow to the end of the receiver's today. A paused
// tracker's past unrecorded entries are still open, so callers that must leave
// paused trackers out filter them.
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
	return s.deleteStillScheduled(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(trackerTime),
		KeyConditionExpression: aws.String("tracker_id = :t AND timeline_at > :now"),
		FilterExpression:       aws.String("open_at > :now"),
		ProjectionExpression:   aws.String("entry_id"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t":   &types.AttributeValueMemberS{Value: trackerID},
			":now": timeKey(now),
		},
	})
}

// DeleteFutureOpenForSchedule deletes the schedule's scheduled entries whose
// occurrence_at is after now, via the schedule-index — what changing or
// removing a schedule replaces. Logged, skipped and already-unrecorded entries
// stay, and each delete is conditional on the entry still being scheduled. It
// returns how many were deleted.
func (s *EntryStore) DeleteFutureOpenForSchedule(ctx context.Context, scheduleID string, now time.Time) (int, error) {
	return s.deleteStillScheduled(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(scheduleIndex),
		KeyConditionExpression: aws.String("schedule_id = :s AND occurrence_at > :now"),
		FilterExpression:       aws.String("attribute_exists(open_at)"),
		ProjectionExpression:   aws.String("entry_id"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":s":   &types.AttributeValueMemberS{Value: scheduleID},
			":now": timeKey(now),
		},
	})
}

// deleteStillScheduled deletes every entry the query finds, each on condition
// that it is still scheduled, and returns how many went.
func (s *EntryStore) deleteStillScheduled(ctx context.Context, in *dynamodb.QueryInput) (int, error) {
	deleted := 0
	for {
		out, err := s.client.Query(ctx, in)
		if err != nil {
			return deleted, err
		}
		for _, item := range out.Items {
			id, ok := item["entry_id"].(*types.AttributeValueMemberS)
			if !ok {
				continue
			}
			gone, err := s.DeleteIfScheduled(ctx, id.Value)
			if err != nil {
				return deleted, err
			}
			if gone {
				deleted++
			}
		}
		if len(out.LastEvaluatedKey) == 0 {
			return deleted, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}

// DeleteIfScheduled deletes the entry if it is still scheduled, and reports
// whether it did. One logged or skipped meanwhile, or already gone, stays as
// it is.
func (s *EntryStore) DeleteIfScheduled(ctx context.Context, entryID string) (bool, error) {
	_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName:                aws.String(s.table),
		Key:                      entryKey(entryID),
		ConditionExpression:      aws.String("#s = :scheduled"),
		ExpressionAttributeNames: map[string]string{"#s": "state"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":scheduled": &types.AttributeValueMemberS{Value: string(domain.EntryScheduled)},
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return false, nil
	}
	return err == nil, err
}

// CreateIfAbsent writes an entry unless one with its id already exists, and
// reports whether it wrote it. The generator's entry ids are deterministic, so
// a re-run, or two runs at once, find the occurrence already there — and an
// occurrence already logged or skipped is never overwritten.
func (s *EntryStore) CreateIfAbsent(ctx context.Context, e domain.Entry) (bool, error) {
	item, err := MarshalItem(e)
	if err != nil {
		return false, err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(entry_id)"),
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return false, nil
	}
	return err == nil, err
}
