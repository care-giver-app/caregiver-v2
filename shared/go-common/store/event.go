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
